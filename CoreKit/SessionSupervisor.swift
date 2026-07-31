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
    /// SSH connection health. Not yet wired to domain suspend/resume — that
    /// lands in a later PR — but tracked here so there is one authority for it.
    enum Health: Sendable, Equatable {
        case connecting
        case connected
        case disconnected
    }

    private let pollInterval: Duration?
    private let initialBackoff: Duration
    private let maxBackoff: Duration
    private let makeSession: SessionFactory

    private var session: Session?
    private var connectTask: Task<Session, any Error>?
    private var bgTask: Task<Void, Never>?
    private(set) var health: Health = .disconnected

    init(
        config: ConnectionConfig,
        domainDbConfig: ModelConfiguration,
        sharedUrl: URL,
        signal: @escaping SignalEnumerator,
        transfers: Transfers,
        pollInterval: Duration?,
        initialBackoff: Duration = .seconds(1),
        maxBackoff: Duration = .seconds(60),
        makeSession: SessionFactory? = nil
    ) {
        self.pollInterval = pollInterval
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff
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

    func disconnect() async {
        bgTask?.cancel()
        bgTask = nil
        connectTask?.cancel()
        connectTask = nil
        await drop()
    }

    /// Drops the live session and marks SSH `disconnected`. The reference is
    /// cleared before awaiting `close()` so a concurrent `connect()` can begin
    /// rebuilding immediately. Leaves the poll loop running so it can recover.
    private func drop() async {
        health = .disconnected
        guard let session else { return }
        self.session = nil
        await session.close()
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
