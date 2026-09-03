import Foundation

extension Transfers where C == ContinuousClock {
    nonisolated public static let shared = Transfers()
}

@MainActor
@Observable
public final class Transfers<C: Clock<Duration>> {
    @ObservationIgnored private var _value: [Transfer] = []

    private let clock: C

    private var signalUpdateTask: Task<Void, Never>?

    nonisolated public init(clock: C = ContinuousClock()) {
        self.clock = clock
    }

    public var value: [Transfer] {
        access(keyPath: \.value)
        return _value
    }

    public var inFlight: Int {
        return value.filter({ transfer in !transfer.progress.isFinished }).count
    }

    public var isActive: Bool {
        signalUpdateTask != nil || !value.isEmpty
    }

    public var uploads: [Transfer] {
        value.filter { $0.progress.fileOperationKind == .uploading }
    }

    public var downloads: [Transfer] {
        value.filter { $0.progress.fileOperationKind == .downloading }
    }

    public var activeUploads: [Transfer] {
        uploads.filter { !$0.progress.isFinished }
    }

    public var activeDownloads: [Transfer] {
        downloads.filter { !$0.progress.isFinished }
    }

    public var isUploading: Bool {
        !uploads.isEmpty
    }

    public var isDownloading: Bool {
        !downloads.isEmpty
    }

    public var totalUnitCount: Int64 {
        value.reduce(0) { $0 + $1.progress.totalUnitCount }
    }

    public var totalUploadUnitCount: Int64 {
        uploads.reduce(0) { $0 + $1.progress.totalUnitCount }
    }

    public var totalDownloadUnitCount: Int64 {
        downloads.reduce(0) { $0 + $1.progress.totalUnitCount }
    }

    public var completedUnitCount: Int64 {
        value.reduce(0) { $0 + $1.progress.completedUnitCount }
    }

    public var completedUploadUnitCount: Int64 {
        uploads.reduce(0) { $0 + $1.progress.completedUnitCount }
    }

    public var completedDownloadUnitCount: Int64 {
        downloads.reduce(0) { $0 + $1.progress.completedUnitCount }
    }

    public var uploadThroughput: Int {
        activeUploads.reduce(0) { $0 + ($1.progress.throughput ?? 0) }
    }

    public var downloadThroughput: Int {
        activeDownloads.reduce(0) { $0 + ($1.progress.throughput ?? 0) }
    }

    public var fractionCompleted: Double {
        totalUnitCount > 0
            ? Double(completedUnitCount) / Double(totalUnitCount)
            : 0
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
            if inFlight == 0 {
                _value.removeAll()
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
}
