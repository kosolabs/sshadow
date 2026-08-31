import Foundation

@MainActor
@Observable
public final class Transfers<C: Clock<Duration>> {
    @ObservationIgnored private var _value: [Transfer] = []

    private let clock: C

    private var signalUpdateTask: Task<Void, Never>?

    nonisolated public init(clock: C) {
        self.clock = clock
    }

    public var value: [Transfer] {
        access(keyPath: \.value)
        return _value
    }

    public var isActive: Bool {
        signalUpdateTask != nil || !value.isEmpty
    }

    func begin(name: String, progress: Progress) -> Transfer {
        let transfer = Transfer(
            name: name,
            progress: progress
        )
        _value.append(transfer)
        triggerSignalUpdate()
        return transfer
    }

    nonisolated func end(transfer: Transfer) {
        Task { @MainActor in
            _value.removeAll { $0 === transfer }
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
