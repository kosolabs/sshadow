import Common
import Foundation
import Testing

@testable import CoreKit

@MainActor
struct EventsTests {
    @Test func addRecordsOperationOutcomeAndInstant() async {
        let events = Events(clock: TestClock())

        let before = Date.now
        events.add(.upload(path: "/f"), outcome: .succeeded(detail: "ok"))
        await waitUntil { events.value.count == 1 }
        let after = Date.now

        #expect(events.value.count == 1)
        let event = events.value[0]
        #expect(event.operation == .upload(path: "/f"))
        #expect(event.outcome == .succeeded(detail: "ok"))
        // `timestamp` is a wall-clock timestamp, stamped independently of the
        // injected (sleep-only) clock.
        #expect(event.timestamp >= before)
        #expect(event.timestamp <= after)
    }

    @Test func addPreservesOrder() async {
        let clock = TestClock()
        let events = Events(clock: clock)

        events.add(.upload(path: "/a"), outcome: .succeeded())
        events.add(.download(path: "/b"), outcome: .cancelled)
        events.add(.remove(path: "/c", kind: .file), outcome: .failed(reason: "x"))

        await waitUntil { events.value.count == 3 }

        #expect(events.value.map(\.operation) == [
            .upload(path: "/a"),
            .download(path: "/b"),
            .remove(path: "/c", kind: .file),
        ])
    }

    @Test func clearRemovesAllRecords() async {
        let events = Events(clock: TestClock())

        events.add(.upload(path: "/a"), outcome: .succeeded())
        events.add(.download(path: "/b"), outcome: .succeeded())
        await waitUntil { events.value.count == 2 }

        events.clear()

        #expect(events.value.isEmpty)
    }

    @Test func rapidAddsCoalesceIntoASingleSignalUpdate() async {
        let clock = TestClock()
        let events = Events(clock: clock)

        events.add(.upload(path: "/a"), outcome: .succeeded())
        events.add(.upload(path: "/b"), outcome: .succeeded())
        events.add(.upload(path: "/c"), outcome: .succeeded())

        // All three records land, but they share one throttled signal task.
        await waitUntil { events.value.count == 3 && clock.pendingCount == 1 }

        #expect(events.value.count == 3)
        #expect(clock.pendingCount == 1)
        #expect(events.isActive)

        // Drain the parked sleep so no continuation is left suspended.
        clock.advance(by: .milliseconds(250))
        await waitUntil { !events.isActive }
    }

    @Test func isActiveDependsOnlyOnThePendingSignalTask() async {
        let clock = TestClock()
        let events = Events(clock: clock)

        #expect(!events.isActive)

        events.add(.upload(path: "/f"), outcome: .succeeded())
        await waitUntil { events.isActive && clock.pendingCount == 1 }
        #expect(events.isActive)

        // Draining the throttle clears isActive even though records remain.
        clock.advance(by: .milliseconds(250))
        await waitUntil { !events.isActive }
        #expect(!events.isActive)
        #expect(events.value.count == 1)
    }
}
