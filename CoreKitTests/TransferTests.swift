import Foundation
import Synchronization
import Testing

@testable import CoreKit

@MainActor
struct TransferTests {
    @Test func storesNameAndProgress() {
        let progress = Progress()
        let transfer = Transfer(name: "file", progress: progress)

        #expect(transfer.name == "file")
        #expect(transfer.progress === progress)
    }

    @Test func updateSignalsProgressObservers() async {
        let transfer = Transfer(name: "file", progress: Progress())
        let fired = Atomic<Bool>(false)

        withObservationTracking {
            _ = transfer.progress
        } onChange: {
            fired.store(true, ordering: .relaxed)
        }

        transfer.update()

        await waitUntil { fired.load(ordering: .relaxed) }
        let didFire = fired.load(ordering: .relaxed)
        #expect(didFire)
    }
}
