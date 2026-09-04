import Foundation

extension Transfers where C == ContinuousClock {
    nonisolated public static let shared = Transfers()
}

@MainActor
@Observable
public final class Transfers<C: Clock<Duration>> {
    @ObservationIgnored private var _value: [Transfer] = []

    private let clock: C
    private let linger: Duration

    private var signalUpdateTask: Task<Void, Never>?

    nonisolated public init(
        clock: C = ContinuousClock(),
        linger: Duration = .seconds(5)
    ) {
        self.clock = clock
        self.linger = linger
    }

    public var value: [Transfer] {
        access(keyPath: \.value)
        return _value
    }

    public var isActive: Bool {
        signalUpdateTask != nil || !active.isEmpty
    }

    public var active: [Transfer] {
        value.filter { !$0.progress.isFinished && !$0.progress.isCancelled }
    }

    public var finished: [Transfer] {
        value.filter { $0.progress.isFinished }
    }

    public var cancelled: [Transfer] {
        value.filter { $0.progress.isCancelled && !$0.progress.isFinished }
    }

    public var activeUploads: [Transfer] {
        active.filter { $0.progress.fileOperationKind == .uploading }
    }

    public var activeDownloads: [Transfer] {
        active.filter { $0.progress.fileOperationKind == .downloading }
    }

    public var isUploading: Bool {
        !activeUploads.isEmpty
    }

    public var isDownloading: Bool {
        !activeDownloads.isEmpty
    }

    public var uploadThroughput: Int {
        activeUploads.reduce(0) { $0 + ($1.progress.throughput ?? 0) }
    }

    public var downloadThroughput: Int {
        activeDownloads.reduce(0) { $0 + ($1.progress.throughput ?? 0) }
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
            try await Task.sleep(for: linger, clock: clock)
            _value.removeAll { $0.id == transfer.id }
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
