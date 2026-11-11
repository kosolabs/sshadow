import Common
import Foundation

private let logger = Logger(category: "Events")

private let maxEvents: Int = 10_000

extension Events where C == ContinuousClock {
    nonisolated public static let shared = Events()
}

@MainActor
@Observable
public final class Events<C: Clock<Duration>> {
    @ObservationIgnored private var _value: [Event] = []
    @ObservationIgnored private var unsaved: [Event] = []
    @ObservationIgnored private var store: AppDB?
    @ObservationIgnored private var lastWrite: Task<Void, Never>?

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

    public func persist(in store: AppDB) async {
        do {
            let saved = try await store.newestEvents(limit: maxEvents)
            withMutation(keyPath: \.value) {
                _value = Array((saved + _value).suffix(maxEvents))
            }
        } catch {
            CoreKit.logger.error("Failed to load saved events: \(error)")
        }
        self.store = store
        saveUnsaved()
    }

    public func clear() {
        withMutation(keyPath: \.value) {
            _value.removeAll()
        }
        unsaved.removeAll()
        write { store in try await store.removeAllEvents() }
    }

    private nonisolated func log(
        _ message: String,
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
                message: message,
                detail: detail
            )
        )
    }

    private nonisolated func append(_ event: Event) {
        Task { @MainActor in
            _value.append(event)
            unsaved.append(event)
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
            saveUnsaved()
            signalUpdateTask = nil
        }
    }

    private func saveUnsaved() {
        guard store != nil, !unsaved.isEmpty else { return }
        let batch = unsaved
        unsaved.removeAll()
        write { store in try await store.append(batch) }
    }

    private func write(_ operation: @escaping @Sendable (AppDB) async throws -> Void) {
        guard let store else { return }
        let previous = lastWrite
        lastWrite = Task {
            await previous?.value
            do {
                try await operation(store)
            } catch {
                CoreKit.logger.error("Failed to save events: \(error)")
            }
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

        public func log(
            level: Event.Level,
            _ message: String,
            detail: String? = nil
        ) {
            eventLog.log(
                message,
                source: source,
                level: level,
                category: category,
                detail: detail
            )
        }

        public func info(_ message: String, detail: String? = nil) {
            log(level: .info, message, detail: detail)
        }

        public func notice(_ message: String, detail: String? = nil) {
            log(level: .notice, message, detail: detail)
        }

        public func warning(_ message: String, detail: String? = nil) {
            log(level: .warning, message, detail: detail)
        }

        public func warning(_ message: String, error: any Error) {
            log(level: .warning, message, detail: error.localizedDescription)
        }

        public func error(_ message: String, detail: String? = nil) {
            log(level: .error, message, detail: detail)
        }

        public func error(_ message: String, error: any Error) {
            log(level: .error, message, detail: error.localizedDescription)
        }
    }
}
