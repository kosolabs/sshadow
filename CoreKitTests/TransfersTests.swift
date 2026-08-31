import Foundation
import Testing

@testable import CoreKit

@MainActor
struct TransfersTests {
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

    @Test func endRemovesOnlyTheMatchingTransfer() async {
        let transfers = Transfers(clock: TestClock())
        let first = transfers.begin(name: "a", progress: Progress())
        let second = transfers.begin(name: "b", progress: Progress())

        transfers.end(transfer: first)

        await waitUntil { transfers.value.count == 1 }

        #expect(transfers.value.count == 1)
        #expect(transfers.value.first === second)
    }

    @Test func isActiveClearsAfterTransferEndsAndSignalDrains() async {
        let clock = TestClock()
        let transfers = Transfers(clock: clock)
        let transfer = transfers.begin(name: "file", progress: Progress())

        #expect(transfers.isActive)

        transfers.end(transfer: transfer)
        await waitUntil { transfers.value.isEmpty && clock.pendingCount == 1 }

        clock.advance(by: .milliseconds(250))
        await waitUntil { !transfers.isActive }
        #expect(!transfers.isActive)
    }
}
