import Common
import FileProvider
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "SessionSupervisor")

actor SessionSupervisor {
    private var config: ConnectionConfig

    private let pollInterval: Duration?
    private let initialBackoff: Duration
    private let maxBackoff: Duration

    private let open: SessionProvider
    private let xpc: XPCBroker
    private let ext: ExtensionController

    private lazy var service = CoreService(supervisor: self)

    private enum OfflineReason {
        case user
    }

    private enum State {
        case offline(OfflineReason)
        case connecting(Task<Void, Never>)
        case online(Session)
    }

    private var state: State = .offline(.user)

    private var session: Session? {
        if case .online(let session) = state { session } else { nil }
    }

    init(
        config: ConnectionConfig,
        pollInterval: Duration?,
        initialBackoff: Duration = .seconds(1),
        maxBackoff: Duration = .seconds(60),
        open: @escaping SessionProvider,
        xpc: XPCBroker? = nil,
        ext: ExtensionController? = nil
    ) {
        self.config = config

        self.pollInterval = pollInterval
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff

        self.open = open
        self.xpc = xpc ?? DomainXPCBroker(domain: config.domain)
        self.ext = ext ?? config.domain
    }

    func connect() async throws {
        let session = try await open(config) { [weak self] in
            guard let self else { return }
            await self.handleFailedSession()
        }
        await ext.resume()
        await xpc.broker(exporting: service)
        state = .online(session)
        await session.startPolling(every: pollInterval)
        logger.info("Session connected: \(config)")
    }

    func disable() async {
        stopReconnecting()
        await session?.stopPolling()
        await xpc.teardown()
        await ext.remove()
        await session?.close()
        state = .offline(.user)
        logger.info("Supervisor disabled: \(config)")
    }

    func pause() async {
        stopReconnecting()
        await session?.stopPolling()
        await xpc.teardown()
        await ext.suspend(
            reason: "The connection is paused. Reconnect it in Settings.",
            options: .temporary
        )
        await session?.close()
        state = .offline(.user)
        logger.info("Supervisor paused: \(config)")
    }

    func reconfigure(config: ConnectionConfig) async throws {
        guard case .offline = state else {
            logger.fatal("reconfigure called while not offline: \(config)")
        }
        self.config = config
        try await connect()
    }
    
    private func reconnect() {
        if case .connecting = state { return }
        state = .connecting(
            Task { [weak self] in
                guard let self else { return }
                await reconnectLoop()
            }
        )
        logger.info("Session reconnecting: \(config)")
    }

    private func reconnectLoop() async {
        var backoff = initialBackoff
        while !Task.isCancelled {
            do {
                try await connect()
                return
            } catch is CancellationError {
                return
            } catch {
                logger.error("Connect failed; retrying in \(backoff): \(error)")
                do { try await Task.sleep(for: backoff) } catch { return }
                backoff = min(backoff * 2, maxBackoff)
            }
        }
    }

    private func handleFailedSession() async {
        await session?.stopPolling()
        await xpc.teardown()
        await ext.suspend(
            reason: "The server is unreachable. Check your network connection.",
            options: .temporary
        )
        await session?.close()
        state = .offline(.user)
        reconnect()
    }

    private func stopReconnecting() {
        if case .connecting(let task) = state { task.cancel() }
    }

    @discardableResult
    func withSession<T: Sendable>(
        _ operation: @Sendable (Session) async throws -> T
    ) async throws -> T {
        guard case .online(let session) = state else {
            throw CoreError.serverUnreachable
        }
        return try await operation(session)
    }
}
