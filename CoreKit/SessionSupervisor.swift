import Common
import FileProvider
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "SessionSupervisor")

actor SessionSupervisor {
    typealias StatusChangeHandler = @Sendable (ConnectionStatus) -> Void
    typealias ReconnectTask = Task<Void, Never>

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
        case disconnecting(OfflineReason)
        case connecting
        case reconnecting(
            ReconnectTask,
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
            let statusChanged = status(of: _state) != status(of: newValue)
            _state = newValue
            if statusChanged {
                onStatusChange(status(of: newValue))
            }
        }
    }

    private func status(of state: State) -> ConnectionStatus {
        switch state {
        case .offline(let reason):
            .offline(reason)
        case .disconnecting(let reason):
            .disconnecting(reason)
        case .connecting:
            .connecting
        case .reconnecting(_, let error, let nextAttempt):
            .reconnecting(error, nextAttempt: nextAttempt)
        case .online:
            .online
        }
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
        guard case .offline = state else { return }
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
        let session = try await openSession(config) { [weak self] error in
            guard let self else { return }
            await self.fail(config: config, error: error)
        }
        await ext.resume()
        await xpc.broker(exporting: service)
        await session.start(pollInterval: pollInterval)

        if case .disconnecting(let reason) = state {
            await disconnect(session, reason: reason)
            return
        }

        state = .online(session)
        log.notice("Connected to \(config.name)")
        logger.notice("Session connected: \(config)")
    }

    func disable() async {
        switch state {
        case .reconnecting(let task, _, _):
            await cancel(task, reason: .disabled)
        case .online(let session):
            await disconnect(session, reason: .disabled)
        default:
            return
        }
        await ext.remove()
        log.notice("Disconnected from \(domain.displayName)")
        logger.notice("Supervisor disabled: \(domain)")
    }

    func pause() async {
        switch state {
        case .reconnecting(let task, _, _):
            await cancel(task, reason: .paused)
        case .online(let session):
            await disconnect(session, reason: .paused)
        default:
            return
        }
        log.notice("Paused connection to \(domain.displayName)")
        logger.notice("Supervisor paused: \(domain)")
    }

    private func fail(config: ConnectionConfig, error: ConnectionError) async {
        guard case .online(let session) = state else { return }
        log.warning("Lost connection to \(config.name)")
        await disconnect(session, reason: .failed(error))
        reconnect(config: config)
    }

    private func cancel(_ task: ReconnectTask, reason: OfflineReason) async {
        state = .disconnecting(reason)
        task.cancel()
        await task.value
        state = .offline(reason)
    }

    private func disconnect(_ session: Session, reason: OfflineReason) async {
        state = .disconnecting(reason)
        await session.stop()
        await xpc.teardown()
        await ext.suspend(reason: reason.text, options: .temporary)
        await session.close()
        state = .offline(reason)
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
