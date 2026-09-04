import Common
import FileProvider
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "SessionSupervisor")

actor SessionSupervisor {
    typealias StatusChangeHandler = @Sendable (ConnectionStatus) -> Void

    private let domain: NSFileProviderDomain

    private let pollInterval: Duration?
    private let initialBackoff: Duration
    private let maxBackoff: Duration

    private let openSession: Session.Provider
    private let xpc: XPCBroker
    private let ext: ExtensionController
    private let events: Events<ContinuousClock>
    private let onStatusChange: StatusChangeHandler
    private var log: Events<ContinuousClock>.Logger

    private lazy var service = CoreService(supervisor: self)

    private enum State {
        case offline(OfflineReason)
        case connecting
        case reconnecting(
            Task<Void, Never>,
            ConnectionError?,
            nextAttempt: Date?
        )
        case online(Session)
    }

    private var _state: State = .offline(.disabled)

    private var state: State {
        get {
            return _state
        }

        set {
            logger.notice("State changed: \(_state) -> \(newValue)")

            if case .reconnecting(let task, _, _) = _state {
                if case .reconnecting = newValue {
                } else {
                    task.cancel()
                }
            }

            _state = newValue
            onStatusChange(status(of: newValue))
        }
    }

    private func status(of state: State) -> ConnectionStatus {
        switch state {
        case .offline(let reason):
            .offline(reason)
        case .connecting:
            .connecting
        case .reconnecting(_, let error, let nextAttempt):
            .reconnecting(error, nextAttempt: nextAttempt)
        case .online:
            .online
        }
    }

    private var session: Session? {
        if case .online(let session) = state { session } else { nil }
    }

    init(
        domain: NSFileProviderDomain,
        pollInterval: Duration?,
        initialBackoff: Duration = .seconds(1),
        maxBackoff: Duration = .seconds(60),
        openSession: @escaping Session.Provider,
        xpc: XPCBroker? = nil,
        ext: ExtensionController? = nil,
        events: Events<ContinuousClock> = .shared,
        onStatusChange: @escaping StatusChangeHandler
    ) {
        self.domain = domain

        self.pollInterval = pollInterval
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff

        self.openSession = openSession
        self.xpc = xpc ?? DomainXPCBroker(domain: domain)
        self.ext = ext ?? domain
        self.events = events
        self.onStatusChange = onStatusChange

        self.log = events.logger(for: .connection)
    }

    func connect(config: ConnectionConfig) async throws(ConnectionError) {
        state = .connecting
        log = events.logger(
            for: .connection,
            source: Event.Source(name: config.name, url: config.url)
        )
        log.info("Connecting to \(config.name)")
        do {
            try await open(config: config)
        } catch {
            log.error(
                "Failed to connect to \(config.name)",
                detail: error.message
            )
            state = .offline(.failed(error))
            throw error
        }
    }

    private func open(config: ConnectionConfig) async throws(ConnectionError) {
        let session = try await openSession(config) { [weak self] in
            guard let self else { return }
            await self.handleFailedSession(config: config)
        }
        await ext.resume()
        await xpc.broker(exporting: service)
        await session.start(pollInterval: pollInterval)
        state = .online(session)
        log.notice("Connected to \(config.name)")
        logger.notice("Session connected: \(config)")
    }

    func disable() async {
        stopReconnecting()
        await session?.stop()
        await xpc.teardown()
        await ext.remove()
        await session?.close()
        state = .offline(.disabled)
        log.notice("Disconnected from \(domain.displayName)")
        logger.notice("Supervisor disabled: \(domain)")
    }

    func pause() async {
        stopReconnecting()
        await session?.stop()
        await xpc.teardown()
        await ext.suspend(
            reason: "The connection is paused. Reconnect it in Settings.",
            options: .temporary
        )
        await session?.close()
        state = .offline(.paused)
        log.notice("Paused connection to \(domain.displayName)")
        logger.notice("Supervisor paused: \(domain)")
    }

    private func handleFailedSession(config: ConnectionConfig) async {
        guard case .online = state else { return }
        log.warning("Lost connection to \(config.name)")
        await session?.stop()
        await xpc.teardown()
        await ext.suspend(
            reason: "The server is unreachable. Check your network connection.",
            options: .temporary
        )
        await session?.close()
        reconnect(config: config)
    }

    private func reconnect(config: ConnectionConfig) {
        if case .reconnecting = state { return }
        state = .reconnecting(
            Task { [weak self] in
                guard let self else { return }
                await reconnectLoop(config: config)
            },
            nil,
            nextAttempt: nil
        )
        logger.notice("Session reconnecting: \(config)")
    }

    private func reconnectLoop(config: ConnectionConfig) async {
        var backoff = initialBackoff
        while !Task.isCancelled {
            do {
                try await open(config: config)
                break
            } catch let error
                where error == .invalidPrivateKey
                || error == .authenticationFailed
                || error == .remotePathNotFound
                || error == .remotePathNotDirectory
            {
                log.error(
                    "Reconnection to \(config.name) failed",
                    detail: error.message
                )
                state = .offline(.failed(error))
                break
            } catch {
                let nextAttempt = Date.now.addingTimeInterval(backoff.seconds)
                setReconnecting(error: error, nextAttempt: nextAttempt)
                log.warning(
                    "Reconnecting to \(config.name)",
                    detail:
                        "Next attempt at \(nextAttempt.formatted(date: .omitted, time: .shortened))"
                )
                logger.error("Connect failed; retrying in \(backoff): \(error)")
                do { try await Task.sleep(for: backoff) } catch { break }
                setReconnecting(error: error, nextAttempt: nil)
                backoff = min(backoff * 2, maxBackoff)
            }
        }
        logger.notice("Reconnect cancelled: \(config)")
    }

    private func setReconnecting(error: ConnectionError?, nextAttempt: Date?) {
        if case .reconnecting(let task, _, _) = state {
            state = .reconnecting(task, error, nextAttempt: nextAttempt)
        }
    }

    private func stopReconnecting() {
        if case .reconnecting(let task, _, _) = state { task.cancel() }
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

extension Duration {
    fileprivate var seconds: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
