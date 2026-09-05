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

    /// How a teardown detaches the File Provider extension.
    private enum Detach: Sendable {
        /// Suspend the domain, preserving its cache.
        case suspend(reason: String)
        /// Remove the domain along with its cache.
        case remove
    }

    /// `offline` and `online` are settled; the rest are transitions, and each
    /// one owns the task driving it.
    ///
    /// Every entry point that moves the supervisor follows the same three
    /// steps, in this order:
    ///
    /// 1. `await settled()`, so a transition already in flight finishes
    ///    rather than interleaving its teardown with our setup;
    /// 2. check the state is one it accepts, and give up if it is not;
    /// 3. claim a transitional state *synchronously*, which locks everyone
    ///    else out for as long as the work takes.
    ///
    /// Only the flow that claimed the state lands the supervisor back in a
    /// settled one, so nothing that suspends mid-transition can be overtaken
    /// and then clobber the result.
    private enum State {
        case offline(OfflineReason)
        case connecting
        case reconnecting(
            Task<Void, Never>,
            ConnectionError?,
            nextAttempt: Date?
        )
        case online(Session)
        case stopping(Task<Void, Never>, reason: OfflineReason)
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

            let previous = status(of: _state)
            _state = newValue

            // `.stopping` already reports the offline reason it is heading
            // for, so that the UI reflects a pause the moment it is asked for
            // rather than once teardown finishes. Report genuine changes only.
            let current = status(of: newValue)
            if current != previous { onStatusChange(current) }
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
        case .stopping(_, let reason):
            .offline(reason)
        }
    }

    private var session: Session? {
        if case .online(let session) = state { session } else { nil }
    }

    /// Whether a connect or reconnect still owns the supervisor. A session
    /// that opens after this goes false belongs to nobody.
    private var isConnecting: Bool {
        switch state {
        case .connecting, .reconnecting: true
        case .offline, .online, .stopping: false
        }
    }

    /// The hand-off of a freshly opened session, while one is in flight. It
    /// lives outside `State` because it spans both `.connecting` and
    /// `.reconnecting`, but `settled()` waits for it just the same.
    private var handoff: Task<Void, Never>?

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

    /// Wait until no transition is in flight. Waiting on a connection being
    /// opened is deliberately not part of this: that can block on the network
    /// for as long as the timeout allows, and a pause must not.
    private func settled() async {
        while true {
            if case .stopping(let task, _) = state {
                await task.value
            } else if let handoff {
                await handoff.value
            } else {
                return
            }
        }
    }

    func connect(config: ConnectionConfig) async throws(ConnectionError) {
        await settled()
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
            // A pause or disable that landed mid-connect owns the outcome.
            if case .connecting = state { state = .offline(.failed(error)) }
            throw error
        }
    }

    private func open(config: ConnectionConfig) async throws(ConnectionError) {
        let session = try await openSession(config) { [weak self] in
            guard let self else { return }
            await self.handleFailedSession(config: config)
        }
        guard isConnecting else {
            // A pause or disable claimed the supervisor while we were opening.
            // Nothing else knows about this session, so close it here.
            logger.notice(
                "Discarding session opened during teardown: \(domain)"
            )
            await session.close()
            return
        }
        let handoff = Task { [weak self] in
            guard let self else { return }
            await install(session, config: config)
        }
        self.handoff = handoff
        await handoff.value
        self.handoff = nil
    }

    /// Wire a freshly opened session up to the extension and the broker.
    private func install(_ session: Session, config: ConnectionConfig) async {
        await ext.resume()
        await xpc.broker(exporting: service)
        await session.start(pollInterval: pollInterval)
        state = .online(session)
        log.notice("Connected to \(config.name)")
        logger.notice("Session connected: \(config)")
    }

    func disable() async {
        await stop(reason: .disabled, detach: .remove)
        log.notice("Disconnected from \(domain.displayName)")
        logger.notice("Supervisor disabled: \(domain)")
    }

    func pause() async {
        await stop(
            reason: .paused,
            detach: .suspend(
                reason: "The connection is paused. Reconnect it in Settings."
            )
        )
        log.notice("Paused connection to \(domain.displayName)")
        logger.notice("Supervisor paused: \(domain)")
    }

    /// Tear the connection down and settle into `.offline(reason)`. Accepts
    /// every state: whatever the supervisor was doing, the user asked for it
    /// to stop. A pause racing a disable therefore runs one after the other
    /// rather than one of them being dropped.
    private func stop(reason: OfflineReason, detach: Detach) async {
        await settled()
        let session = self.session
        let task = Task { [weak self] in
            guard let self else { return }
            await finishStop(
                session: session,
                detach: detach,
                reason: reason
            )
        }
        state = .stopping(task, reason: reason)
        await task.value
    }

    private func finishStop(
        session: Session?,
        detach: Detach,
        reason: OfflineReason
    ) async {
        await teardown(session: session, detach: detach)
        state = .offline(reason)
    }

    private func teardown(session: Session?, detach: Detach) async {
        await session?.stop()
        await xpc.teardown()
        switch detach {
        case .suspend(let reason):
            await ext.suspend(reason: reason, options: .temporary)
        case .remove:
            await ext.remove()
        }
        await session?.close()
    }

    private func handleFailedSession(config: ConnectionConfig) async {
        await settled()
        guard case .online(let session) = state else { return }
        log.warning("Lost connection to \(config.name)")
        state = .reconnecting(
            Task { [weak self] in
                await self?.reconnect(config: config, closing: session)
            },
            nil,
            nextAttempt: nil
        )
        logger.notice("Session reconnecting: \(config)")
    }

    /// Tear the lost session down, then retry with backoff. Runs as the task
    /// `.reconnecting` was claimed with, so by the time it starts a pause or
    /// disable may already have taken the supervisor away from it.
    private func reconnect(
        config: ConnectionConfig,
        closing session: Session
    ) async {
        guard case .reconnecting = state else {
            // The teardown that replaced us never saw this session, since we
            // still held `.online` when it read the state.
            await session.close()
            return
        }
        // A pause or disable can still claim the supervisor partway through
        // this teardown, and `settled()` deliberately does not wait on it the
        // way it waits on a hand-off: every call here is itself a teardown, so
        // a claim can only land after we have issued ours, and the destructive
        // one always arrives last. The supervisor ends where the user asked.
        await teardown(
            session: session,
            detach: .suspend(
                reason:
                    "The server is unreachable. Check your network connection."
            )
        )
        await reconnectLoop(config: config)
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
                if case .reconnecting = state {
                    state = .offline(.failed(error))
                }
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
