import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "SessionSupervisor")

/// Owns a single domain's live SSH `Session`: builds it (coalescing concurrent
/// callers onto one in-flight connect), runs the periodic poll loop, and
/// recovers from SSH disconnects. The session's SSH connection is immutable, so
/// recovery means replacing the whole `Session` — which is why ownership lives
/// here rather than inside `Session` itself.
///
/// Health is a small state machine:
///
///     connecting ──success──▶ connected
///         ▲                       │
///         │                    disconnect
///         └────── retry ◀── disconnected
///
/// A `connectionFailed` from a request (via `withSession`) or a poll drops the
/// dead session and transitions to `disconnected`; the poll loop then retries
/// `connect()` on a backoff until it recovers. This is the single recovery path.
@MainActor
final class SessionSupervisor {
    /// Shown in Finder while a domain is suspended because its server dropped.
    static let unreachableReason =
        "The server is currently unreachable; check your network connection."

    /// SSH connection health, the supervisor's own half of composite health.
    enum Health: Sendable, Equatable {
        case connecting
        case connected
        case disconnected
    }

    private let config: ConnectionConfig
    private let domainDbConfig: ModelConfiguration
    private let sharedUrl: URL
    private let signal: SignalEnumerator
    private let transfers: Transfers

    private let pollInterval: Duration?
    private let initialBackoff: Duration
    private let maxBackoff: Duration
    private var service: CoreService!

    private var session: Session?
    private var connectTask: Task<Session, any Error>?
    private var bgTask: Task<Void, Never>?
    private(set) var health: Health = .disconnected
    private var connection: NSXPCConnection?

    private var domain: NSFileProviderDomain { config.domain }

    /// Whether the XPC link is currently brokered — the other half of composite
    /// health. The domain is resumed only when SSH is `connected` *and* the XPC
    /// link is up, so a re-broker can never resume a domain whose server is down.
    private var xpcUp = false

    init(
        config: ConnectionConfig,
        domainDbConfig: ModelConfiguration,
        sharedUrl: URL,
        signal: @escaping SignalEnumerator,
        transfers: Transfers,
        pollInterval: Duration?,
        initialBackoff: Duration = .seconds(1),
        maxBackoff: Duration = .seconds(60)
    ) {
        self.config = config
        self.domainDbConfig = domainDbConfig
        self.sharedUrl = sharedUrl
        self.signal = signal
        self.transfers = transfers

        self.pollInterval = pollInterval
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff

        self.service = CoreService(supervisor: self)
    }

    /// Returns the live session, connecting if needed. Concurrent callers
    /// coalesce onto one in-flight connect (single-flight).
    @discardableResult
    func connect() async throws -> Session {
        if let session {
            return session
        }

        if let connectTask {
            return try await connectTask.value
        }

        health = .connecting
        let task = Task {
            let ssh = try await SSHClient.connect(config: config)
            let sftp = try await ssh.sftp()
            let db = try await DomainDB.open(config: domainDbConfig)
            return Session(
                config: config,
                ssh: ssh,
                sftp: sftp,
                db: db,
                sharedUrl: sharedUrl,
                signal: signal,
                transfers: transfers
            )
        }
        connectTask = task

        do {
            let session = try await task.value
            self.session = session
            connectTask = nil
            health = .connected
            start()
            await reconcileDomainState()
            return session
        } catch {
            connectTask = nil
            health = .disconnected
            throw error
        }
    }

    /// Runs `operation` against the live session. If it fails because the SSH
    /// connection dropped, transitions to `disconnected` and drops the dead
    /// session so the next `connect()` rebuilds it. This is the recovery path
    /// shared by request and poll failures.
    @discardableResult
    func withSession<T: Sendable>(
        _ operation: @Sendable (Session) async throws -> T
    ) async throws -> T {
        let session = try await connect()
        do {
            return try await operation(session)
        } catch let error as SSHError where error.isConnectionFailed {
            logger.error("SSH disconnected: \(error)")
            await drop()
            throw error
        }
    }

    /// Shuts the supervisor down: cancels the poll loop, tears down the XPC
    /// link, and closes the session. Does not suspend the domain — this is an
    /// intentional teardown (disable/forget), not a server drop.
    func disconnect() async {
        bgTask?.cancel()
        bgTask = nil
        connectTask?.cancel()
        connectTask = nil
        health = .disconnected
        xpcUp = false
        await teardown()
        await closeSession()
    }

    /// Marks SSH `disconnected` on a server drop: closes the dead session and
    /// suspends the domain with a user-facing reason. Leaves the poll loop
    /// running so it can reconnect and later resume.
    private func drop() async {
        health = .disconnected
        await closeSession()
        await suspend(reason: Self.unreachableReason)
    }

    /// Releases the live session. The reference is cleared before awaiting
    /// `close()` so a concurrent `connect()` can begin rebuilding immediately.
    private func closeSession() async {
        guard let session else { return }
        self.session = nil
        await session.close()
    }

    /// Called after the XPC link (re)brokers. Marks the link up and reconciles;
    /// gating means a re-broker while the server is down will not resume.
    private func handleBrokered() async {
        xpcUp = true
        await reconcileDomainState()
    }

    /// The single authority on domain suspend/resume: resumes only when both
    /// halves of composite health are good (SSH connected *and* XPC up).
    private func reconcileDomainState() async {
        guard health == .connected, xpcUp else { return }
        await resume()
    }

    private func start() {
        guard bgTask == nil, let pollInterval else { return }
        bgTask = Task { [weak self] in
            await self?.run(pollInterval: pollInterval)
        }
    }

    /// Poll + recovery loop. While connected it polls every `pollInterval`; on a
    /// failure it backs off, then the next iteration's `connect()` rebuilds the
    /// session. Backoff resets once a connection is (re)established.
    private func run(pollInterval: Duration) async {
        var backoff = initialBackoff
        while !Task.isCancelled {
            do {
                try await connect()
                backoff = initialBackoff
                try await Task.sleep(for: pollInterval)
                try await poll()
            } catch is CancellationError {
                return
            } catch {
                logger.error(
                    "Poll loop error; retrying in \(backoff): \(error)"
                )
                do {
                    try await Task.sleep(for: backoff)
                } catch {
                    return
                }
                backoff = min(backoff * 2, maxBackoff)
            }
        }
    }

    private func poll() async throws {
        try await withSession { try await $0.poll() }
    }

    /// (Re)establishes the XPC link: connects, exports the core service, and
    /// attaches the extension. Tears down any existing connection first, so it
    /// is safe to call repeatedly. Does not touch domain suspend/resume — that
    /// is the supervisor's decision, taken in `onBrokered`.
    func broker() async throws {
        await teardown()

        let domainId = domain.id
        let connection = try await requireConnection()
        connection.exportedInterface = NSXPCInterface(with: CoreXPC.self)
        connection.exportedObject = service
        connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
        connection.invalidationHandler = { [weak self] in
            logger.info("Invalidated XPC: \(domainId)")
            Task { @MainActor in
                guard let self else { return }
                self.connection = nil
                do {
                    try await self.broker()
                } catch {
                    logger.error(
                        "Failed to broker XPC for \(domainId): \(error)"
                    )
                }
            }
        }
        connection.interruptionHandler = { connection.invalidate() }
        connection.resume()
        self.connection = connection

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.attach()

        logger.info("Brokered XPC: \(domainId)")
    }

    private func requireConnection() async throws -> NSXPCConnection {
        while true {
            do {
                return try await domain.service.fileProviderConnection()
            } catch {
                logger.error("Failed to broker XPC for \(domain.id): \(error)")
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Detaches the extension and invalidates the connection. Clears the
    /// handlers first so the intentional invalidation does not trigger a
    /// re-broker. A no-op when there is no live connection.
    func teardown() async {
        xpcUp = false
        guard let connection else { return }
        self.connection = nil

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.detach()
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()

        logger.info("Tore down XPC: \(domain.id)")
    }

    /// Suspends the domain with a user-facing reason. Best-effort: failures are
    /// logged, not thrown, since suspend runs on error/shutdown paths.
    func suspend(reason: String) async {
        do {
            try await domain.suspend(reason: reason, options: .temporary)
            logger.info("Suspended sync: \(domain.id)")
        } catch {
            logger.error("Failed to suspend \(domain.id): \(error)")
        }
    }

    /// Resumes the domain. A safe no-op when the domain is already connected.
    /// Best-effort: failures are logged, not thrown.
    func resume() async {
        do {
            try await domain.resume()
            logger.info("Resumed sync: \(domain.id)")
        } catch {
            logger.error("Failed to resume \(domain.id): \(error)")
        }
    }
}
