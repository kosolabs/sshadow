import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "SessionSupervisor")

actor SessionSupervisor {
    private let config: ConnectionConfig
    private let domainDbConfig: ModelConfiguration
    private let sharedUrl: URL
    private let signal: SignalEnumerator
    private let transfers: Transfers

    private let pollInterval: Duration?
    private let initialBackoff: Duration
    private let maxBackoff: Duration
    private let ext: ExtensionController

    private lazy var service = CoreService(supervisor: self)

    private enum SSHState {
        case offline
        case online(Session)
    }

    private var state: SSHState = .offline
    private var connectTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var connection: NSXPCConnection?

    init(
        config: ConnectionConfig,
        domainDbConfig: ModelConfiguration,
        sharedUrl: URL,
        signal: @escaping SignalEnumerator,
        transfers: Transfers,
        pollInterval: Duration?,
        initialBackoff: Duration = .seconds(1),
        maxBackoff: Duration = .seconds(60),
        ext: ExtensionController
    ) {
        self.config = config
        self.domainDbConfig = domainDbConfig
        self.sharedUrl = sharedUrl
        self.signal = signal
        self.transfers = transfers

        self.pollInterval = pollInterval
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff
        self.ext = ext
    }

    func enable() async {
        startConnecting()
    }

    func disable() async {
        stopConnecting()
        stopPolling()
        await teardownXpc()
        await ext.remove()
        if case .online(let session) = state {
            await session.close()
        }
        state = .offline
        logger.info("Supervisor disabled: \(config)")
    }

    func connectForTests() async throws {
        let session = try await connectSsh()
        state = .online(session)
    }

    private func connect() async throws {
        let session = try await connectSsh()
        stopConnecting()
        await ext.resume()
        await brokerXpc()
        startPolling()
        state = .online(session)
        logger.info("Session online: \(config)")
    }

    private func reconnect() async {
        stopPolling()
        await teardownXpc()
        await ext.suspend(
            reason: "The server is unreachable. Check your network connection.",
            options: .temporary
        )
        if case .online(let session) = state {
            await session.close()
        }
        startConnecting()
        state = .offline
        logger.info("Session offline: \(config)")
    }

    private func startConnecting() {
        guard connectTask == nil else { return }
        connectTask = Task { [weak self] in
            guard let self else { return }
            var backoff = initialBackoff
            while !Task.isCancelled {
                do {
                    try await connect()
                    return
                } catch is CancellationError {
                    return
                } catch {
                    logger.error(
                        "Connect failed; retrying in \(backoff): \(error)"
                    )
                    do { try await Task.sleep(for: backoff) } catch { return }
                    backoff = min(backoff * 2, maxBackoff)
                }
            }
        }
    }

    private func stopConnecting() {
        connectTask?.cancel()
        connectTask = nil
    }

    private func startPolling() {
        guard pollTask == nil, let pollInterval else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: pollInterval)
                    try await withSession { try await $0.poll() }
                } catch is CancellationError {
                    return
                } catch {
                    logger.error("Poll error: \(error)")
                }
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    @discardableResult
    func withSession<T: Sendable>(
        _ operation: @Sendable (Session) async throws -> T
    ) async throws -> T {
        guard case .online(let session) = state else {
            throw CoreError.serverUnreachable
        }

        do {
            return try await operation(session)
        } catch let error as SSHError
            where error.isConnectionFailed || error.sftpError == .failure
            || error.sftpError == .connectionLost
            || error.sftpError == .noConnection
        {
            logger.error("SSH connection lost: \(error)")
            await reconnect()
            throw CoreError.serverUnreachable
        }
    }

    @discardableResult
    private func connectSsh() async throws -> Session {
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

    private func brokerXpc() async {
        guard connection == nil else { return }

        let connection = await awaitXpc()
        connection.exportedInterface = NSXPCInterface(with: CoreXPC.self)
        connection.exportedObject = service
        connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
        connection.invalidationHandler = { [weak self] in
            Task {
                guard let self else { return }
                await self.rebrokerXpc()
            }
        }
        connection.interruptionHandler = { connection.invalidate() }
        connection.resume()

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.attach()
        self.connection = connection

        logger.info("XPC brokered: \(config)")
    }

    private func awaitXpc() async -> NSXPCConnection {
        while true {
            do {
                return try await config.domain.service.fileProviderConnection()
            } catch {
                logger.error("Failed to broker XPC for \(config): \(error)")
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func rebrokerXpc() async {
        logger.info("XPC invalidated: \(config)")
        connection = nil
        await brokerXpc()
    }

    private func teardownXpc() async {
        guard let connection else { return }
        self.connection = nil

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.detach()
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()

        logger.info("XPC torn down: \(config)")
    }
}
