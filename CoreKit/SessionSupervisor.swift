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
/// `state` is a small state machine:
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

    private let config: ConnectionConfig
    private let domainDbConfig: ModelConfiguration
    private let sharedUrl: URL
    private let signal: SignalEnumerator
    private let transfers: Transfers

    private let pollInterval: Duration?
    private let initialBackoff: Duration
    private let maxBackoff: Duration
    private var service: CoreService!

    /// The SSH connection lifecycle as a single value: `disconnected`, an
    /// in-flight `connecting` connect (single-flight), or a live `connected`
    /// session. Folding session + connect task + health into one enum keeps them
    /// in lockstep and makes illegal states — such as connecting while a session
    /// is already live — unrepresentable.
    private enum State {
        case disconnected
        case connecting(Task<Session, any Error>)
        case connected(Session)
    }

    private var state: State = .disconnected
    private var bgTask: Task<Void, Never>?
    private var connection: NSXPCConnection?

    private var domain: NSFileProviderDomain { config.domain }

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
        switch state {
        case .connected(let session):
            return session
        case .connecting(let task):
            return try await task.value
        case .disconnected:
            break
        }

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
        state = .connecting(task)

        do {
            let session = try await task.value
            state = .connected(session)
            start()
            await reconcileDomainState()
            return session
        } catch {
            state = .disconnected
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

        // Capture any live session before clearing state, then close it after
        // teardown; cancel an in-flight connect instead.
        let session: Session?
        switch state {
        case .connecting(let task):
            task.cancel()
            session = nil
        case .connected(let live):
            session = live
        case .disconnected:
            session = nil
        }
        state = .disconnected

        await teardown()
        await session?.close()
    }

    /// Marks SSH `disconnected` on a server drop: closes the dead session and
    /// suspends the domain with a user-facing reason. Leaves the poll loop
    /// running so it can reconnect and later resume.
    private func drop() async {
        await closeSession()
        await suspend(reason: Self.unreachableReason)
    }

    /// Releases the live session, if any. The state is cleared before awaiting
    /// `close()` so a concurrent `connect()` can begin rebuilding immediately.
    private func closeSession() async {
        guard case .connected(let session) = state else { return }
        state = .disconnected
        await session.close()
    }

    /// The single authority on domain suspend/resume: resumes only when both
    /// halves of composite health are good (SSH `connected` *and* the XPC link
    /// up, i.e. `connection` non-nil). Gating on the link means a re-broker while
    /// the server is down will not resume, and an SSH reconnect while the link is
    /// down will not resume either.
    private func reconcileDomainState() async {
        guard case .connected = state, connection != nil else { return }
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
    /// is safe to call repeatedly. Reconciles once the link is up so a resume
    /// gated on composite health can take effect.
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

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.attach()
        self.connection = connection

        logger.info("Brokered XPC: \(domainId)")
        await reconcileDomainState()
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
