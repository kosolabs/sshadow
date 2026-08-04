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
actor SessionSupervisor {
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
    private lazy var service = CoreService(supervisor: self)

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
    }

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
            startPolling()
            await resumeIfHealthy()
            return session
        } catch {
            state = .disconnected
            throw error
        }
    }

    func shutdown() async {
        stopPolling()

        switch state {
        case .connecting(let task):
            task.cancel()
            await teardown()
        case .connected(let session):
            await teardown()
            await session.close()
        case .disconnected:
            await teardown()
        }
        state = .disconnected
    }

    @discardableResult
    func withSession<T: Sendable>(
        _ operation: @Sendable (Session) async throws -> T
    ) async throws -> T {
        let session = try await connect()
        do {
            return try await operation(session)
        } catch let error as SSHError where error.isConnectionFailed {
            logger.error("SSH disconnected: \(error)")
            await disconnect()
            await suspend(reason: Self.unreachableReason)
            throw error
        }
    }

    private func disconnect() async {
        guard case .connected(let session) = state else { return }
        state = .disconnected
        await session.close()
    }

    private func startPolling() {
        guard bgTask == nil, let pollInterval else { return }
        bgTask = Task { [weak self] in
            guard let self else { return }
            await self.pollLoop(interval: pollInterval)
        }
    }

    private func pollLoop(interval: Duration) async {
        var backoff = initialBackoff
        while !Task.isCancelled {
            do { try await Task.sleep(for: interval) } catch { return }
            do {
                try await withSession { try await $0.poll() }
                backoff = initialBackoff
            } catch {
                logger.error(
                    "Poll loop error; retrying in \(backoff): \(error)"
                )
                do { try await Task.sleep(for: backoff) } catch { return }
                backoff = min(backoff * 2, maxBackoff)
            }
        }
    }

    private func stopPolling() {
        guard let bgTask else { return }
        bgTask.cancel()
        self.bgTask = nil
    }

    func broker() async throws {
        await teardown()

        let domainId = domain.id
        let connection = try await awaitConnection()
        connection.exportedInterface = NSXPCInterface(with: CoreXPC.self)
        connection.exportedObject = service
        connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
        connection.invalidationHandler = { [weak self] in
            logger.info("Invalidated XPC: \(domainId)")
            Task {
                guard let self else { return }
                await self.rebroker()
            }
        }
        connection.interruptionHandler = { connection.invalidate() }
        connection.resume()

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.attach()
        self.connection = connection

        logger.info("Brokered XPC: \(domainId)")
        await resumeIfHealthy()
    }

    private func rebroker() async {
        do {
            connection = nil
            try await broker()
        } catch {
            logger.error("Failed to broker XPC for \(domain.id): \(error)")
        }
    }

    private func awaitConnection() async throws -> NSXPCConnection {
        while true {
            do {
                return try await domain.service.fileProviderConnection()
            } catch {
                logger.error("Failed to broker XPC for \(domain.id): \(error)")
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

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

    private func resumeIfHealthy() async {
        guard case .connected = state, connection != nil else { return }
        await resume()
    }

    private func resume() async {
        do {
            try await domain.resume()
            logger.info("Resumed sync: \(domain.id)")
        } catch {
            logger.error("Failed to resume \(domain.id): \(error)")
        }
    }

    private func suspend(reason: String) async {
        do {
            try await domain.suspend(reason: reason, options: .temporary)
            logger.info("Suspended sync: \(domain.id)")
        } catch {
            logger.error("Failed to suspend \(domain.id): \(error)")
        }
    }
}
