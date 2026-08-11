import Common
import FileProvider
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "SessionSupervisor")

actor SessionSupervisor {
    private let config: ConnectionConfig

    private let pollInterval: Duration?
    private let initialBackoff: Duration
    private let maxBackoff: Duration

    private let connect: SessionProvider
    private let xpc: XPCBroker
    private let ext: ExtensionController

    private lazy var service = CoreService(supervisor: self)

    private enum SSHState {
        case offline
        case online(Session)
    }

    private var state: SSHState = .offline
    private var connectTask: Task<Void, Never>?

    private var session: Session? {
        if case .online(let session) = state { session } else { nil }
    }

    init(
        config: ConnectionConfig,
        pollInterval: Duration?,
        initialBackoff: Duration = .seconds(1),
        maxBackoff: Duration = .seconds(60),
        connect: @escaping SessionProvider,
        xpc: XPCBroker? = nil,
        ext: ExtensionController? = nil
    ) {
        self.config = config

        self.pollInterval = pollInterval
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff

        self.connect = connect
        self.xpc = xpc ?? DomainXPCBroker(domain: config.domain)
        self.ext = ext ?? config.domain
    }

    func enable() async {
        startConnecting()
    }

    func disable() async {
        stopConnecting()
        await session?.stopPolling()
        await xpc.teardown()
        await ext.remove()
        await session?.close()
        state = .offline
        logger.info("Supervisor disabled: \(config)")
    }

    private func goOnline() async throws {
        let session = try await connect(config) { [weak self] in
            guard let self else { return }
            await self.goOffline()
        }
        stopConnecting()
        await ext.resume()
        await xpc.broker(exporting: service)
        state = .online(session)
        await session.startPolling(every: pollInterval)
        logger.info("Session online: \(config)")
    }

    private func goOffline() async {
        await session?.stopPolling()
        await xpc.teardown()
        await ext.suspend(
            reason: "The server is unreachable. Check your network connection.",
            options: .temporary
        )
        await session?.close()
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
                    try await goOnline()
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
