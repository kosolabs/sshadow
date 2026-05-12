import Foundation
import Testing

@testable import Common

struct SpeedometerTests {
    private func makeProgress() -> Progress {
        let progress = Progress()
        progress.kind = .file
        progress.fileOperationKind = .downloading
        return progress
    }

    @Test func initConfiguresProgress() {
        let progress = makeProgress()
        _ = Speedometer(progress: progress, totalUnitCount: 100)

        #expect(progress.totalUnitCount == 100)
        #expect(progress.completedUnitCount == 0)
        #expect(progress.fileTotalCount == 1)
        #expect(progress.fileCompletedCount == 0)
    }

    @Test func finalizeHandlesZeroByteProgress() {
        let progress = makeProgress()
        let speedometer = Speedometer(progress: progress, totalUnitCount: 0)

        let description = speedometer.finalize()

        #expect(progress.throughput == 0)
        #expect(progress.estimatedTimeRemaining == nil)
        #expect(progress.isFinished)
        #expect(progress.fileCompletedCount == 1)
        #expect(!description.isEmpty)
    }

    @Test func finalizeMarksFullyTransferredProgressAsComplete() {
        let progress = makeProgress()
        let speedometer = Speedometer(
            progress: progress,
            totalUnitCount: 1024,
            frequency: 0
        )

        speedometer.update(delta: 1024)
        let description = speedometer.finalize()

        #expect(progress.completedUnitCount == 1024)
        #expect(progress.isFinished)
        #expect(progress.fileCompletedCount == 1)
        #expect(progress.estimatedTimeRemaining == nil)
        #expect(!description.isEmpty)
    }

    @Test func updateAccumulatesCompletedUnitCount() {
        let progress = makeProgress()
        let speedometer = Speedometer(
            progress: progress,
            totalUnitCount: 100,
            frequency: 0
        )

        speedometer.update(delta: 30)
        speedometer.update(delta: 20)

        #expect(progress.completedUnitCount == 50)
    }

    @Test func updateReturnsNilBeforeFrequencyElapses() {
        let progress = makeProgress()
        let speedometer = Speedometer(
            progress: progress,
            totalUnitCount: 100,
            frequency: 60
        )

        let result = speedometer.update(delta: 10)

        #expect(result == nil)
        #expect(progress.completedUnitCount == 10)
    }

    @Test func updateReturnsDescriptionWhenFrequencyHasElapsed() {
        let progress = makeProgress()
        let speedometer = Speedometer(
            progress: progress,
            totalUnitCount: 100,
            frequency: 0
        )

        let result = speedometer.update(delta: 50)

        #expect(result != nil)
        #expect(result?.isEmpty == false)
    }

    @Test func initRespectsCompletedUnitCount() {
        let progress = makeProgress()
        let speedometer = Speedometer(
            progress: progress,
            totalUnitCount: 100,
            completedUnitCount: 25,
            frequency: 0
        )

        #expect(progress.completedUnitCount == 25)

        speedometer.update(delta: 25)
        #expect(progress.completedUnitCount == 50)
    }
}
