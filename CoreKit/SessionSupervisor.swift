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
    private let xpc: XPCBroker
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
        xpc: XPCBroker? = nil,
        ext: ExtensionController? = nil
    ) {
        self.config = config
        self.domainDbConfig = domainDbConfig
        self.sharedUrl = sharedUrl
        self.signal = signal
        self.transfers = transfers

        self.pollInterval = pollInterval
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff
        self.xpc = xpc ?? DomainXPCBroker(domain: config.domain)
        self.ext = ext ?? config.domain
    }

    func enable() async {
        startConnecting()
    }

    func disable() async {
        stopConnecting()
        stopPolling()
        await xpc.teardown()
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
        await xpc.broker(exporting: service)
        startPolling()
        state = .online(session)
        logger.info("Session online: \(config)")
    }

    private func reconnect() async {
        stopPolling()
        await xpc.teardown()
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
}
