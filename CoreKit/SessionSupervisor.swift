import Common
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "SessionSupervisor")

/// Builds a connected `Session`. Injected so tests can drive reconnect and
/// recovery deterministically; production uses the default that dials SSH.
typealias SessionFactory = @Sendable () async throws -> Session

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
actor SessionSupervisor {
    /// Shown in Finder while a domain is suspended because its server dropped.
    static let unreachableReason =
        "The server is currently unreachable; check your network connection."

    /// SSH connection health, the supervisor's own half of composite health.
    enum Health: Sendable, Equatable {
        case connecting
        case connected
        case disconnected
    }

    private let pollInterval: Duration?
    private let initialBackoff: Duration
    private let maxBackoff: Duration
    private let makeSession: SessionFactory

    /// The domain's XPC link to the extension — the supervisor's main-actor arm.
    let link: DomainLink

    private var session: Session?
    private var connectTask: Task<Session, any Error>?
    private var bgTask: Task<Void, Never>?
    private(set) var health: Health = .disconnected

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
        maxBackoff: Duration = .seconds(60),
        link: DomainLink? = nil,
        makeSession: SessionFactory? = nil
    ) {
        self.pollInterval = pollInterval
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff
        self.link = link ?? DomainLink(domain: config.domain)
        self.makeSession = makeSession ?? {
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
        let task = Task { try await makeSession() }
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

    /// Brokers the domain's XPC link to the extension, then reconciles domain
    /// state (resuming only when SSH is also connected).
    func broker() async throws {
        await link.setOnBrokered { [weak self] in
            await self?.handleBrokered()
        }
        try await link.broker()
    }

    /// Tears down the domain's XPC link to the extension.
    func teardown() async {
        xpcUp = false
        await link.teardown()
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
        await link.teardown()
        await closeSession()
    }

    /// Marks SSH `disconnected` on a server drop: closes the dead session and
    /// suspends the domain with a user-facing reason. Leaves the poll loop
    /// running so it can reconnect and later resume.
    private func drop() async {
        health = .disconnected
        await closeSession()
        await link.suspend(reason: Self.unreachableReason)
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
        await link.resume()
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
                logger.error("Poll loop error; retrying in \(backoff): \(error)")
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
}
