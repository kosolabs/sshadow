import Foundation
import Synchronization
import Testing

@testable import Common

struct ThroughputEstimatorTests {
    private func makeProgress() -> Progress {
        let progress = Progress()
        progress.kind = .file
        progress.fileOperationKind = .downloading
        return progress
    }

    @Test func initConfiguresProgress() {
        let progress = makeProgress()
        _ = ThroughputEstimator(progress: progress, totalUnitCount: 100)

        #expect(progress.totalUnitCount == 100)
        #expect(progress.completedUnitCount == 0)
        #expect(progress.fileTotalCount == 1)
        #expect(progress.fileCompletedCount == 0)
    }

    @Test func initRespectsCompletedUnitCount() {
        let progress = makeProgress()
        let estimator = ThroughputEstimator(
            progress: progress,
            totalUnitCount: 100,
            completedUnitCount: 25
        )

        #expect(progress.completedUnitCount == 25)

        estimator.update(delta: 25)
        #expect(progress.completedUnitCount == 50)
    }

    @Test func updateAccumulatesCompletedUnitCount() {
        let progress = makeProgress()
        let estimator = ThroughputEstimator(progress: progress, totalUnitCount: 100)

        estimator.update(delta: 30)
        estimator.update(delta: 20)

        #expect(progress.completedUnitCount == 50)
    }

    @Test func finalizeHandlesZeroByteProgress() {
        let progress = makeProgress()
        let estimator = ThroughputEstimator(progress: progress, totalUnitCount: 0)

        estimator.finalize()

        #expect(progress.throughput == 0)
        #expect(progress.estimatedTimeRemaining == nil)
        #expect(progress.isFinished)
        #expect(progress.fileCompletedCount == 1)
    }

    @Test func finalizeMarksFullyTransferredProgressAsComplete() {
        let progress = makeProgress()
        let estimator = ThroughputEstimator(progress: progress, totalUnitCount: 1024)

        estimator.update(delta: 1024)
        estimator.finalize()

        #expect(progress.completedUnitCount == 1024)
        #expect(progress.isFinished)
        #expect(progress.fileCompletedCount == 1)
        #expect(progress.estimatedTimeRemaining == nil)
    }

    @Test func updateNotifiesReporters() {
        let progress = makeProgress()
        let updates = Atomic(0)
        let estimator = ThroughputEstimator(
            progress: progress,
            totalUnitCount: 100,
            reporters: [
                ThrottledProgressReporter(
                    frequency: 0,
                    onUpdate: { _ in updates.add(1, ordering: .relaxed) }
                )
            ]
        )

        estimator.update(delta: 50)

        #expect(updates.load(ordering: .relaxed) == 1)
    }

    @Test func finalizeNotifiesReporters() {
        let progress = makeProgress()
        let finalized = Atomic(0)
        let estimator = ThroughputEstimator(
            progress: progress,
            totalUnitCount: 100,
            reporters: [
                ThrottledProgressReporter(
                    onFinalize: { _ in finalized.add(1, ordering: .relaxed) }
                )
            ]
        )

        estimator.finalize()

        #expect(finalized.load(ordering: .relaxed) == 1)
    }
}
