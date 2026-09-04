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
        source: Event.Source? = nil
    ) -> Logger {
        Logger(
            eventLog: self,
            source: source,
            category: category
        )
    }

    public func clear() {
        withMutation(keyPath: \.value) {
            _value.removeAll()
        }
    }

    private nonisolated func log(
        _ message: LogMessage,
        source: Event.Source?,
        level: Event.Level,
        category: Event.Category,
        detail: String?
    ) {
        append(
            Event(
                timestamp: Date.now,
                source: source,
                level: level,
                category: category,
                message: message.display,
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
        private let source: Event.Source?

        init(
            eventLog: Events<C>,
            source: Event.Source?,
            category: Event.Category
        ) {
            self.eventLog = eventLog
            self.source = source
            self.category = category
        }

        public func info(_ message: LogMessage, detail: String? = nil) {
            eventLog.log(
                message,
                source: source,
                level: .info,
                category: category,
                detail: detail
            )
        }

        public func notice(_ message: LogMessage, detail: String? = nil) {
            eventLog.log(
                message,
                source: source,
                level: .notice,
                category: category,
                detail: detail
            )
        }

        public func warning(_ message: LogMessage, detail: String? = nil) {
            eventLog.log(
                message,
                source: source,
                level: .warning,
                category: category,
                detail: detail
            )
        }

        public func warning(_ message: LogMessage, error: any Error) {
            eventLog.log(
                message,
                source: source,
                level: .warning,
                category: category,
                detail: error.localizedDescription
            )
        }

        public func error(_ message: LogMessage, detail: String? = nil) {
            eventLog.log(
                message,
                source: source,
                level: .error,
                category: category,
                detail: detail
            )
        }

        public func error(_ message: LogMessage, error: any Error) {
            eventLog.log(
                message,
                source: source,
                level: .error,
                category: category,
                detail: error.localizedDescription
            )
        }
    }
}
