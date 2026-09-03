import Common
import Foundation

private let maxEvents: Int = 1000

extension Events where C == ContinuousClock {
    nonisolated public static let shared = Events()
}

@MainActor
@Observable
public final class Events<C: Clock<Duration>> {
    @ObservationIgnored private var _value: [Event] = []

    private let clock: C

    private var signalUpdateTask: Task<Void, Never>?

    public var value: [Event] {
        access(keyPath: \.value)
        return _value
    }

    public var isActive: Bool {
        signalUpdateTask != nil
    }

    public nonisolated init(clock: C = ContinuousClock()) {
        self.clock = clock
    }

    public nonisolated func logger(
        for category: Event.Category,
        connectionId: UUID
    ) -> Logger {
        Logger(
            eventLog: self,
            category: category,
            connectionId: connectionId
        )
    }

    public func clear() {
        withMutation(keyPath: \.value) {
            _value.removeAll()
        }
    }
    
    private nonisolated func log(
        _ message: String,
        level: Event.Level,
        category: Event.Category,
        connectionId: UUID,
        detail: String?
    ) {
        append(
            Event(
                timestamp: Date.now,
                connectionId: connectionId,
                level: level,
                category: category,
                message: message,
                detail: detail
            )
        )
    }

    private nonisolated func append(_ event: Event) {
        Task { @MainActor in
            _value.append(event)
            if _value.count > maxEvents {
                _value.removeFirst(_value.count - maxEvents)
            }
            triggerSignalUpdate()
        }
    }

    private func triggerSignalUpdate() {
        guard signalUpdateTask == nil else { return }
        signalUpdateTask = Task {
            try? await Task.sleep(for: .milliseconds(250), clock: clock)
            withMutation(keyPath: \.value) {}
            signalUpdateTask = nil
        }
    }

    public struct Logger {
        private let eventLog: Events<C>
        private let category: Event.Category
        private let connectionId: UUID

        init(
            eventLog: Events<C>,
            category: Event.Category,
            connectionId: UUID
        ) {
            self.eventLog = eventLog
            self.category = category
            self.connectionId = connectionId
        }

        public func info(_ message: String, detail: String? = nil) {
            eventLog.log(
                message,
                level: .info,
                category: category,
                connectionId: connectionId,
                detail: detail
            )
        }

        public func notice(_ message: String, detail: String? = nil) {
            eventLog.log(
                message,
                level: .notice,
                category: category,
                connectionId: connectionId,
                detail: detail
            )
        }

        public func warning(_ message: String, detail: String? = nil) {
            eventLog.log(
                message,
                level: .warning,
                category: category,
                connectionId: connectionId,
                detail: detail
            )
        }

        public func warning(_ message: String, error: any Error) {
            eventLog.log(
                message,
                level: .warning,
                category: category,
                connectionId: connectionId,
                detail: error.localizedDescription
            )
        }

        public func error(_ message: String, detail: String? = nil) {
            eventLog.log(
                message,
                level: .error,
                category: category,
                connectionId: connectionId,
                detail: detail
            )
        }

        public func error(_ message: String, error: any Error) {
            eventLog.log(
                message,
                level: .error,
                category: category,
                connectionId: connectionId,
                detail: error.localizedDescription
            )
        }
    }
}
