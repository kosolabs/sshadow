import Foundation
import Testing

@testable import CoreKit

@MainActor
struct TransfersTests {
    /// Builds a `Progress` configured like a real transfer so the aggregate
    /// helpers on `Transfers` have direction, unit counts, and throughput to
    /// work with. A transfer is "finished" once `completed >= total`.
    private func makeProgress(
        kind: Progress.FileOperationKind,
        total: Int64 = 100,
        completed: Int64 = 0,
        throughput: Int? = nil
    ) -> Progress {
        let progress = Progress()
        progress.kind = .file
        progress.fileOperationKind = kind
        progress.totalUnitCount = total
        progress.completedUnitCount = completed
        if let throughput {
            progress.throughput = throughput
        }
        return progress
    }

    // MARK: - begin

    @Test func beginAppendsAndReturnsTransfer() {
        let transfers = Transfers(clock: TestClock())
        let progress = Progress()

        let transfer = transfers.begin(name: "file", progress: progress)

        #expect(transfers.value.count == 1)
        #expect(transfers.value.first === transfer)
        #expect(transfer.name == "file")
        #expect(transfer.progress === progress)
    }

    @Test func beginMakesTransfersActive() {
        let transfers = Transfers(clock: TestClock())

        #expect(!transfers.isActive)
        _ = transfers.begin(name: "file", progress: Progress())
        #expect(transfers.isActive)
    }

    // MARK: - end

    @Test func endClearsAllTransfersWhenNothingInFlight() async {
        let transfers = Transfers(clock: TestClock())
        let first = transfers.begin(
            name: "a",
            progress: makeProgress(kind: .downloading, total: 100, completed: 100)
        )
        _ = transfers.begin(
            name: "b",
            progress: makeProgress(kind: .uploading, total: 100, completed: 100)
        )

        #expect(transfers.inFlight == 0)

        transfers.end(transfer: first)

        await waitUntil { transfers.value.isEmpty }
        #expect(transfers.value.isEmpty)
    }

    @Test func endKeepsAllTransfersWhileAnyInFlight() async {
        let clock = TestClock()
        let transfers = Transfers(clock: clock)
        let first = transfers.begin(
            name: "a",
            progress: makeProgress(kind: .downloading, total: 100, completed: 100)
        )
        _ = transfers.begin(
            name: "b",
            progress: makeProgress(kind: .downloading, total: 100, completed: 50)
        )

        #expect(transfers.inFlight == 1)

        transfers.end(transfer: first)

        // The signal task scheduled during begin is our barrier that the async
        // end() has had a chance to run. Because a transfer is still in flight,
        // nothing should have been removed.
        await waitUntil { clock.pendingCount == 1 }
        #expect(transfers.value.count == 2)
    }

    @Test func isActiveClearsAfterTransferEndsAndSignalDrains() async {
        let clock = TestClock()
        let transfers = Transfers(clock: clock)
        let transfer = transfers.begin(
            name: "file",
            progress: makeProgress(kind: .downloading, total: 100, completed: 100)
        )

        #expect(transfers.isActive)

        transfers.end(transfer: transfer)
        await waitUntil { transfers.value.isEmpty && clock.pendingCount == 1 }

        clock.advance(by: .milliseconds(250))
        await waitUntil { !transfers.isActive }
        #expect(!transfers.isActive)
    }

    // MARK: - direction partitioning

    @Test func partitionsTransfersByDirection() {
        let transfers = Transfers(clock: TestClock())
        _ = transfers.begin(name: "up", progress: makeProgress(kind: .uploading))
        _ = transfers.begin(name: "down", progress: makeProgress(kind: .downloading))

        #expect(transfers.uploads.map(\.name) == ["up"])
        #expect(transfers.downloads.map(\.name) == ["down"])
        #expect(transfers.isUploading)
        #expect(transfers.isDownloading)
    }

    @Test func directionFlagsAreFalseWhenNoMatchingTransfers() {
        let transfers = Transfers(clock: TestClock())
        _ = transfers.begin(name: "up", progress: makeProgress(kind: .uploading))

        #expect(transfers.isUploading)
        #expect(!transfers.isDownloading)
    }

    @Test func activeCollectionsExcludeFinishedTransfers() {
        let transfers = Transfers(clock: TestClock())
        _ = transfers.begin(
            name: "up-active",
            progress: makeProgress(kind: .uploading, total: 100, completed: 50)
        )
        _ = transfers.begin(
            name: "up-done",
            progress: makeProgress(kind: .uploading, total: 100, completed: 100)
        )
        _ = transfers.begin(
            name: "down-active",
            progress: makeProgress(kind: .downloading, total: 100, completed: 10)
        )
        _ = transfers.begin(
            name: "down-done",
            progress: makeProgress(kind: .downloading, total: 100, completed: 100)
        )

        #expect(transfers.activeUploads.map(\.name) == ["up-active"])
        #expect(transfers.activeDownloads.map(\.name) == ["down-active"])
        #expect(transfers.inFlight == 2)
    }

    // MARK: - unit-count aggregation

    @Test func aggregatesUnitCountsByDirection() {
        let transfers = Transfers(clock: TestClock())
        _ = transfers.begin(
            name: "up",
            progress: makeProgress(kind: .uploading, total: 100, completed: 40)
        )
        _ = transfers.begin(
            name: "down",
            progress: makeProgress(kind: .downloading, total: 200, completed: 60)
        )

        #expect(transfers.totalUnitCount == 300)
        #expect(transfers.totalUploadUnitCount == 100)
        #expect(transfers.totalDownloadUnitCount == 200)
        #expect(transfers.completedUnitCount == 100)
        #expect(transfers.completedUploadUnitCount == 40)
        #expect(transfers.completedDownloadUnitCount == 60)
    }

    @Test func fractionCompletedReflectsAggregateProgress() {
        let transfers = Transfers(clock: TestClock())
        _ = transfers.begin(
            name: "a",
            progress: makeProgress(kind: .downloading, total: 100, completed: 25)
        )
        _ = transfers.begin(
            name: "b",
            progress: makeProgress(kind: .downloading, total: 100, completed: 75)
        )

        #expect(transfers.fractionCompleted == 0.5)
    }

    @Test func fractionCompletedIsZeroWithoutTotalUnits() {
        let transfers = Transfers(clock: TestClock())

        #expect(transfers.fractionCompleted == 0)
    }

    // MARK: - throughput aggregation

    @Test func throughputSumsActiveTransfersByDirection() {
        let transfers = Transfers(clock: TestClock())
        _ = transfers.begin(
            name: "up1",
            progress: makeProgress(kind: .uploading, total: 100, completed: 10, throughput: 100)
        )
        _ = transfers.begin(
            name: "up2",
            progress: makeProgress(kind: .uploading, total: 100, completed: 20, throughput: 200)
        )
        _ = transfers.begin(
            name: "up-done",
            progress: makeProgress(kind: .uploading, total: 100, completed: 100, throughput: 999)
        )
        _ = transfers.begin(
            name: "down",
            progress: makeProgress(kind: .downloading, total: 100, completed: 30, throughput: 300)
        )

        #expect(transfers.uploadThroughput == 300)
        #expect(transfers.downloadThroughput == 300)
    }
}
