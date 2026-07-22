import Common
import Foundation

@MainActor
@Observable
public final class Transfer: Identifiable {
    private let _progress: Progress
    public let name: String

    public var progress: Progress {
        access(keyPath: \.progress)
        return _progress
    }

    private func signalProgressChanged() {
        withMutation(keyPath: \.progress) {}
    }

    public init(name: String, progress: Progress) {
        self.name = name
        self._progress = progress
    }

    nonisolated public func update() {
        Task { @MainActor in
            signalProgressChanged()
        }
    }
}
