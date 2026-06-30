import Foundation
import Synchronization

public final class ThrottledProgressReporter: Sendable {
    private let frequency: UInt64
    private let onUpdate: @Sendable (Progress) -> Void
    private let onFinalize: @Sendable (Progress) -> Void
    private let lastUpdate: Atomic<UInt64>

    public init(
        frequency: TimeInterval = 1.0,
        onUpdate: @escaping @Sendable (Progress) -> Void = { _ in },
        onFinalize: @escaping @Sendable (Progress) -> Void = { _ in }
    ) {
        self.frequency = UInt64(frequency * 1_000_000_000)
        self.onUpdate = onUpdate
        self.onFinalize = onFinalize
        self.lastUpdate = Atomic(DispatchTime.now().uptimeNanoseconds)
    }

    public func update(_ progress: Progress) {
        let now = DispatchTime.now().uptimeNanoseconds
        if now - lastUpdate.load(ordering: .relaxed) >= frequency {
            lastUpdate.store(now, ordering: .relaxed)
            onUpdate(progress)
        }
    }

    public func finalize(_ progress: Progress) {
        onFinalize(progress)
    }
}
