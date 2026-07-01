import Foundation
import Synchronization
import Testing

@testable import Common

struct ThrottledProgressReporterTests {
    @Test func updateFiresWhenFrequencyHasElapsed() {
        let progress = Progress()
        let updates = Atomic(0)
        let reporter = ThrottledProgressReporter(
            frequency: 0,
            onUpdate: { _ in updates.add(1, ordering: .relaxed) }
        )

        reporter.update(progress)

        #expect(updates.load(ordering: .relaxed) == 1)
    }

    @Test func updateThrottlesBeforeFrequencyElapses() {
        let progress = Progress()
        let updates = Atomic(0)
        let reporter = ThrottledProgressReporter(
            frequency: 60,
            onUpdate: { _ in updates.add(1, ordering: .relaxed) }
        )

        reporter.update(progress)

        #expect(updates.load(ordering: .relaxed) == 0)
    }

    @Test func finalizeAlwaysInvokesOnFinalize() {
        let progress = Progress()
        let finalized = Atomic(0)
        let reporter = ThrottledProgressReporter(
            frequency: 60,
            onFinalize: { _ in finalized.add(1, ordering: .relaxed) }
        )

        reporter.finalize(progress)

        #expect(finalized.load(ordering: .relaxed) == 1)
    }
}
