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

    /// `Task.sleep(for:clock:)` reads `clock.now` when the task body runs, so
    /// advancing before a sleeper has parked pushes its deadline past the new
    /// `now` and it never fires. Every test below waits for the expected number
    /// of parked sleepers before advancing: one for the throttle `begin`
    /// schedules, plus one per outstanding `end`.
    private func waitForSleepers(
        _ count: Int,
        on clock: TestClock
    ) async {
        await waitUntil { clock.pendingCount == count }
        #expect(clock.pendingCount == count)
    }

    @Test func endKeepsTransferVisibleUntilLingerElapses() async {
        let clock = TestClock()
        let transfers = Transfers(clock: clock, linger: .seconds(5))
        let transfer = transfers.begin(
            name: "a",
            progress: makeProgress(
                kind: .downloading,
                total: 100,
                completed: 100
            )
        )

        transfers.end(transfer: transfer)
        await waitForSleepers(2, on: clock)

        // Short of the linger: begin's throttle drains, the removal does not.
        clock.advance(by: .seconds(4))
        await waitUntil { clock.pendingCount == 1 }

        #expect(clock.pendingCount == 1)
        #expect(transfers.value.count == 1)
    }

    @Test func endRemovesTransferAfterLingerElapses() async {
        let clock = TestClock()
        let transfers = Transfers(clock: clock, linger: .seconds(5))
        let transfer = transfers.begin(
            name: "a",
            progress: makeProgress(
                kind: .downloading,
                total: 100,
                completed: 100
            )
        )

        transfers.end(transfer: transfer)
        await waitForSleepers(2, on: clock)
        #expect(transfers.value.count == 1)

        clock.advance(by: .seconds(5))

        await waitUntil { transfers.value.isEmpty }
        #expect(transfers.value.isEmpty)
    }

    @Test func endRemovesOnlyTheEndedTransfer() async {
        let clock = TestClock()
        let transfers = Transfers(clock: clock, linger: .seconds(5))
        let first = transfers.begin(
            name: "a",
            progress: makeProgress(
                kind: .downloading,
                total: 100,
                completed: 100
            )
        )
        _ = transfers.begin(
            name: "b",
            progress: makeProgress(
                kind: .downloading,
                total: 100,
                completed: 50
            )
        )

        transfers.end(transfer: first)
        await waitForSleepers(2, on: clock)

        clock.advance(by: .seconds(5))

        await waitUntil { transfers.value.map(\.name) == ["b"] }
        #expect(transfers.value.map(\.name) == ["b"])
    }

    @Test func isActiveClearsWhileFinishedTransfersLinger() async {
        let clock = TestClock()
        let transfers = Transfers(clock: clock, linger: .seconds(5))
        let transfer = transfers.begin(
            name: "file",
            progress: makeProgress(
                kind: .downloading,
                total: 100,
                completed: 100
            )
        )

        #expect(transfers.isActive)

        transfers.end(transfer: transfer)
        await waitForSleepers(2, on: clock)

        // Draining begin's throttle clears isActive even though the finished
        // transfer is still lingering in `value` — the menu bar stops spinning
        // while the row stays on screen showing its outcome.
        clock.advance(by: .milliseconds(250))
        await waitUntil { !transfers.isActive }

        #expect(!transfers.isActive)
        #expect(transfers.value.count == 1)
    }

    // MARK: - direction partitioning

    @Test func partitionsTransfersByDirection() {
        let transfers = Transfers(clock: TestClock())
        _ = transfers.begin(
            name: "up",
            progress: makeProgress(kind: .uploading)
        )
        _ = transfers.begin(
            name: "down",
            progress: makeProgress(kind: .downloading)
        )

        #expect(transfers.activeUploads.map(\.name) == ["up"])
        #expect(transfers.activeDownloads.map(\.name) == ["down"])
        #expect(transfers.isUploading)
        #expect(transfers.isDownloading)
    }

    @Test func directionFlagsAreFalseWhenNoMatchingTransfers() {
        let transfers = Transfers(clock: TestClock())
        _ = transfers.begin(
            name: "up",
            progress: makeProgress(kind: .uploading)
        )

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
            progress: makeProgress(
                kind: .downloading,
                total: 100,
                completed: 10
            )
        )
        _ = transfers.begin(
            name: "down-done",
            progress: makeProgress(
                kind: .downloading,
                total: 100,
                completed: 100
            )
        )

        #expect(transfers.activeUploads.map(\.name) == ["up-active"])
        #expect(transfers.activeDownloads.map(\.name) == ["down-active"])
        #expect(transfers.active.count == 2)
    }

    // MARK: - throughput aggregation

    @Test func throughputSumsActiveTransfersByDirection() {
        let transfers = Transfers(clock: TestClock())
        _ = transfers.begin(
            name: "up1",
            progress: makeProgress(
                kind: .uploading,
                total: 100,
                completed: 10,
                throughput: 100
            )
        )
        _ = transfers.begin(
            name: "up2",
            progress: makeProgress(
                kind: .uploading,
                total: 100,
                completed: 20,
                throughput: 200
            )
        )
        _ = transfers.begin(
            name: "up-done",
            progress: makeProgress(
                kind: .uploading,
                total: 100,
                completed: 100,
                throughput: 999
            )
        )
        _ = transfers.begin(
            name: "down",
            progress: makeProgress(
                kind: .downloading,
                total: 100,
                completed: 30,
                throughput: 300
            )
        )

        #expect(transfers.uploadThroughput == 300)
        #expect(transfers.downloadThroughput == 300)
    }
}
