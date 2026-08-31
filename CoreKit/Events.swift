import Common
import Foundation

private let logger = Logger(category: "Events")

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

    nonisolated public init(clock: C) {
        self.clock = clock
    }

    nonisolated func add(
        _ operation: Event.Operation,
        outcome: Event.Outcome
    ) {
        let record = Event(
            timestamp: Date.now,
            operation: operation,
            outcome: outcome
        )

        switch outcome {
        case .succeeded(let detail):
            if let detail {
                logger.info("Completed \(operation): \(detail)")
            } else {
                logger.info("Completed \(operation)")
            }
        case .failed(let reason):
            logger.error("Failed to \(operation): \(reason)")
        case .cancelled:
            logger.info("Cancelled \(operation)")
        }

        Task { @MainActor in
            _value.append(record)
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
}
