import Common
import FileProvider
import Foundation
import SwiftRussh

private let logger = Logger(category: "SessionSupervisor")

package actor SessionSupervisor {
    typealias StatusChangeHandler = @Sendable (ConnectionStatus) -> Void
    typealias ConnectTask = Task<Result<Void, ConnectionError>, Never>
    typealias ReconnectTask = Task<Void, Never>

    private let domain: NSFileProviderDomain

    private let initialBackoff: Duration

    private let openSession: Session.Provider
    private let xpc: XPCBroker
    private let ext: ExtensionController
    private let events: Events<ContinuousClock>
    private let onStatusChange: StatusChangeHandler
    private var log: Events<ContinuousClock>.Logger

    private lazy var service = CoreService(supervisor: self)

    private enum State: CustomStringConvertible {
        case offline(OfflineReason)
        case disconnecting(OfflineReason)
        case connecting(ConnectTask, ConnectionConfig)
        case reconnecting(
            ReconnectTask,
            ConnectionConfig,
            ConnectionError?,
            nextAttempt: Date?
        )
        case online(Session, ConnectionConfig)

        var description: String {
            switch self {
            case .offline(let reason):
                "offline(\(reason))"
            case .disconnecting(let reason):
                "disconnecting(\(reason))"
            case .connecting:
                "connecting"
            case .reconnecting(_, _, let error, let nextAttempt):
                "reconnecting(error: \(error.map(String.init(describing:)) ?? "nil"), "
                    + "nextAttempt: \(nextAttempt.map(String.init(describing:)) ?? "nil"))"
            case .online:
                "online"
            }
        }
    }

    private var _state: State = .offline(.disabled)

    private var state: State {
        get {
            return _state
        }

        set {
            logger.info("State changed: \(_state) -> \(newValue)")
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
        case .reconnecting(_, _, let error, let nextAttempt):
            .reconnecting(error, nextAttempt: nextAttempt)
        case .online:
            .online
        }
    }

    var status: ConnectionStatus {
        status(of: state)
    }

    init(
        domain: NSFileProviderDomain,
        initialBackoff: Duration = .seconds(1),
        openSession: @escaping Session.Provider,
        xpc: XPCBroker? = nil,
        ext: ExtensionController? = nil,
        events: Events<ContinuousClock> = .shared,
        onStatusChange: @escaping StatusChangeHandler
    ) {
        self.domain = domain

        self.initialBackoff = initialBackoff

        self.openSession = openSession
        self.xpc =
            xpc
            ?? DomainXPCBroker(domain: domain, extensionUrl: .builtInExtension)
        self.ext = ext ?? domain
        self.events = events
        self.onStatusChange = onStatusChange

        self.log = events.logger(for: .connection)
    }

    func connect(config: ConnectionConfig) async throws(ConnectionError) {
        guard case .offline = state else { return }
        setLogSource(config)
        log.info("Connecting to \(config.name)")
        logger.notice("Connecting: \(config.detailedDescription)")

        let task: ConnectTask = Task {
            do throws(ConnectionError) {
                try await open(config: config)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        state = .connecting(task, config)

        switch await task.value {
        case .success:
            guard case .online = state else { throw .cancelled }
        case .failure(let error):
            guard case .connecting = state else { throw .cancelled }
            log.error(
                "Failed to connect to \(config.name)",
                detail: error.detail
            )
            state = .offline(.failed(error))
            throw error
        }
    }

    private func open(config: ConnectionConfig) async throws(ConnectionError) {
        let session = try await openSession(config) { [weak self] error in
            guard let self else { return }
            await self.fail(error: error)
        }
        await ext.resume()
        await xpc.broker(exporting: service) { [weak self] otherExtension in
            // Not awaited: the first brokering runs inside the task that
            // going offline cancels.
            Task { await self?.unreachable(otherExtension: otherExtension) }
        }
        await session.start()

        if case .disconnecting(let reason) = state {
            await disconnect(session, reason: reason)
            return
        }

        let latest = startingConfig ?? config
        state = .online(session, latest)
        if latest != config {
            await session.update(from: latest)
        }
        if await xpc.ready() {
            await ext.retryUnreachable()
        }
        log.notice("Connected to \(config.name)")
        logger.notice("Supervisor connected: \(config)")
    }

    func reconnect(config: ConnectionConfig) {
        guard case .offline = state else { return }
        setLogSource(config)
        state = .reconnecting(
            Task { [weak self] in
                guard let self else { return }
                await reconnectLoop()
            },
            config,
            nil,
            nextAttempt: nil
        )
        logger.notice("Session reconnecting: \(config.detailedDescription)")
    }

    func disable() async {
        switch state {
        case .offline:
            state = .offline(.disabled)
            break
        case .connecting(let task, _):
            await cancel(task, reason: .disabled)
        case .reconnecting(let task, _, _, _):
            await cancel(task, reason: .disabled)
        case .online(let session, _):
            await disconnect(session, reason: .disabled)
        case .disconnecting:
            state = .disconnecting(.disabled)
        }
        await ext.remove()
        log.notice("Disconnected from \(domain.displayName)")
        logger.notice("Supervisor disabled: \(domain)")
    }

    func pause() async {
        switch state {
        case .connecting(let task, _):
            await cancel(task, reason: .paused)
        case .reconnecting(let task, _, _, _):
            await cancel(task, reason: .paused)
        case .online(let session, _):
            await disconnect(session, reason: .paused)
        case .offline(.failed), .offline(.xpcUnreachable):
            state = .offline(.paused)
            await ext.suspend(
                reason: OfflineReason.paused.text,
                options: .temporary
            )
        case .offline, .disconnecting:
            logger.info("Ignored pause while in \(state)")
            return
        }
        log.notice("Paused connection to \(domain.displayName)")
        logger.notice("Supervisor paused: \(domain)")
    }

    func update(config newConfig: ConnectionConfig) async {
        switch state {
        case .connecting(let task, let config) where config != newConfig:
            state = .connecting(task, newConfig)
        case .reconnecting(let task, let config, let error, let nextAttempt)
        where config != newConfig:
            state = .reconnecting(
                task,
                newConfig,
                error,
                nextAttempt: nextAttempt
            )
        case .online(let session, let config) where config != newConfig:
            state = .online(session, newConfig)
            await session.update(from: newConfig)
        default:
            return
        }
        logger.notice("Live settings updated: \(newConfig.detailedDescription)")
    }

    private func fail(error: ConnectionError) async {
        guard case .online(let session, let config) = state else { return }
        log.warning("Lost connection to \(config.name)")
        await disconnect(session, reason: .failed(error))
        reconnect(config: config)
    }

    private func unreachable(otherExtension: URL?) async {
        let reason = OfflineReason.xpcUnreachable(
            otherExtension: otherExtension
        )
        switch state {
        case .connecting(let task, _):
            await cancel(task, reason: reason)
        case .reconnecting(let task, _, _, _):
            await cancel(task, reason: reason)
        case .online(let session, _):
            await disconnect(session, reason: reason)
        case .offline, .disconnecting:
            return
        }
        log.error(
            "SSHadow can't connect to its extension",
            detail: otherExtension.map {
                interferenceDetail(
                    other: $0.containingApp,
                    own: Bundle.main.bundleURL,
                    home: .userHome
                )
            } ?? "Choose How to Fix… from the SSHadow menu."
        )
        logger.notice("Supervisor went offline: \(domain): \(reason)")
    }

    private func cancel<T>(
        _ task: Task<T, Never>,
        reason: OfflineReason
    ) async {
        state = .disconnecting(reason)
        task.cancel()
        _ = await task.value
        state = .offline(disconnectingReason ?? reason)
    }

    private func disconnect(_ session: Session, reason: OfflineReason) async {
        state = .disconnecting(reason)
        await Task {
            await session.stop()
            await xpc.teardown()
            await ext.suspend(reason: reason.text, options: .temporary)
            await session.close()
        }.value
        state = .offline(disconnectingReason ?? reason)
    }

    private var startingConfig: ConnectionConfig? {
        switch state {
        case .connecting(_, let config), .reconnecting(_, let config, _, _):
            config
        case .offline, .disconnecting, .online:
            nil
        }
    }

    private var disconnectingReason: OfflineReason? {
        guard case .disconnecting(let reason) = state else { return nil }
        return reason
    }

    private func setLogSource(_ config: ConnectionConfig) {
        log = events.logger(
            for: .connection,
            source: Event.Source(name: config.name, url: config.url)
        )
    }

    private func reconnectLoop() async {
        guard var config = startingConfig else { return }
        var backoff = min(initialBackoff, config.maxReconnectDelay)
        while !Task.isCancelled {
            guard let latest = startingConfig else { break }
            config = latest
            do {
                try await open(config: config)
                break
            } catch let error where !error.isRetryable {
                log.error(
                    "Reconnection to \(config.name) failed",
                    detail: error.detail
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
                backoff = min(backoff * 2, config.maxReconnectDelay)
            }
        }
        logger.notice("Reconnect cancelled: \(config)")
    }

    private func setReconnecting(error: ConnectionError?, nextAttempt: Date?) {
        if case .reconnecting(let task, let config, _, _) = state {
            state = .reconnecting(task, config, error, nextAttempt: nextAttempt)
        }
    }

    @discardableResult
    func withSession<T: Sendable>(
        _ operation: @Sendable (Session) async throws -> T
    ) async throws -> T {
        guard case .online(let session, _) = state else {
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
