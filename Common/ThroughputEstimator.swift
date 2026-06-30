import Foundation
import Synchronization

public final class ThroughputEstimator: Sendable {
    private let start: UInt64
    private let progress: Progress
    private let smoothing: Double
    private let reporters: [ThrottledProgressReporter]
    private let lastSample: Atomic<UInt64>

    public init(
        progress: Progress,
        totalUnitCount: Int64,
        completedUnitCount: Int64 = 0,
        smoothing: TimeInterval = 1.0,
        reporters: [ThrottledProgressReporter] = []
    ) {
        self.progress = progress
        self.smoothing = smoothing
        self.reporters = reporters

        self.start = DispatchTime.now().uptimeNanoseconds
        self.lastSample = Atomic(start)

        self.progress.totalUnitCount = totalUnitCount
        self.progress.completedUnitCount = completedUnitCount
        self.progress.fileTotalCount = 1
        self.progress.fileCompletedCount = 0
    }

    public func update(delta: Int) {
        self.progress.completedUnitCount += Int64(delta)

        let now = DispatchTime.now().uptimeNanoseconds
        let interval = now - lastSample.exchange(now, ordering: .relaxed)
        sample(bytes: delta, interval: interval)

        for reporter in reporters {
            reporter.update(progress)
        }
    }

    public func finalize() {
        let interval = DispatchTime.now().uptimeNanoseconds - start
        sample(interval: interval)

        for reporter in reporters {
            reporter.finalize(progress)
        }
    }

    private func sample(bytes: Int? = nil, interval: UInt64) {
        let bytes = bytes ?? Int(self.progress.totalUnitCount)

        if interval > 0 && bytes > 0 {
            let total = Double(progress.totalUnitCount)
            let completed = Double(progress.completedUnitCount)
            let instant = Double(bytes) / Double(interval) * 1_000_000_000

            let throughput: Double
            if let previous = progress.throughput, previous > 0 {
                let dt = Double(interval) / 1_000_000_000
                let alpha = 1 - exp(-dt / smoothing)
                throughput = Double(previous) + alpha * (instant - Double(previous))
            } else {
                throughput = instant
            }

            progress.throughput = Int(throughput)
            progress.estimatedTimeRemaining = (total - completed) / throughput
        } else {
            progress.throughput = 0
            progress.estimatedTimeRemaining = nil
        }

        if progress.totalUnitCount == 0 && progress.completedUnitCount == 0 {
            progress.totalUnitCount = 1
            progress.completedUnitCount = 1
        }

        if progress.isFinished {
            self.progress.fileCompletedCount = 1
            self.progress.estimatedTimeRemaining = nil
        }
    }
}
