import Common
import Foundation
import Testing

@testable import CoreKit

@MainActor
struct EventsTests {
    private struct SampleError: LocalizedError {
        var errorDescription: String? { "something went wrong" }
    }

    @Test func loggerStoresEntryWithInstantAndFields() async {
        let events = Events(clock: TestClock())
        let connectionId = UUID()
        let log = events.logger(for: .file, connectionId: connectionId)

        let before = Date.now
        log.info("Upload /f", detail: "ok")
        await waitUntil { events.value.count == 1 }
        let after = Date.now

        #expect(events.value.count == 1)
        let event = events.value[0]
        #expect(event.message == "Upload /f")
        #expect(event.level == .info)
        #expect(event.category == .file)
        #expect(event.detail == "ok")
        #expect(event.connectionId == connectionId)
        // `timestamp` is a wall-clock timestamp, stamped independently of the
        // injected (sleep-only) clock.
        #expect(event.timestamp >= before)
        #expect(event.timestamp <= after)
    }

    @Test func loggerMapsEachMethodOntoItsLevel() async {
        let events = Events(clock: TestClock())
        let log = events.logger(for: .connection, connectionId: UUID())

        log.info("a")
        log.notice("b")
        log.warning("c")
        log.error("d")

        await waitUntil { events.value.count == 4 }

        #expect(events.value.map(\.level) == [.info, .notice, .warning, .error])
    }

    @Test func loggerRecordsErrorDescriptionAsDetail() async {
        let events = Events(clock: TestClock())
        let log = events.logger(for: .connection, connectionId: UUID())

        log.warning("Reconnecting", error: SampleError())
        log.error("Failed", error: SampleError())

        await waitUntil { events.value.count == 2 }

        #expect(events.value[0].level == .warning)
        #expect(events.value[0].detail == "something went wrong")
        #expect(events.value[1].level == .error)
        #expect(events.value[1].detail == "something went wrong")
    }

    @Test func loggerCarriesItsCategoryAndConnectionId() async {
        let events = Events(clock: TestClock())
        let syncId = UUID()
        let fileId = UUID()
        let syncLog = events.logger(for: .sync, connectionId: syncId)
        let fileLog = events.logger(for: .file, connectionId: fileId)

        syncLog.notice("synced")
        fileLog.info("downloaded")

        await waitUntil { events.value.count == 2 }

        #expect(events.value[0].category == .sync)
        #expect(events.value[0].connectionId == syncId)
        #expect(events.value[1].category == .file)
        #expect(events.value[1].connectionId == fileId)
    }

    @Test func logsPreserveOrder() async {
        let events = Events(clock: TestClock())
        let log = events.logger(for: .file, connectionId: UUID())

        log.info("a")
        log.info("b")
        log.info("c")

        await waitUntil { events.value.count == 3 }

        #expect(events.value.map(\.message) == ["a", "b", "c"])
    }

    @Test func clearRemovesAllEntries() async {
        let events = Events(clock: TestClock())
        let log = events.logger(for: .file, connectionId: UUID())

        log.info("a")
        log.info("b")
        await waitUntil { events.value.count == 2 }

        events.clear()

        #expect(events.value.isEmpty)
    }

    @Test func rapidLogsCoalesceIntoASingleSignalUpdate() async {
        let clock = TestClock()
        let events = Events(clock: clock)
        let log = events.logger(for: .file, connectionId: UUID())

        log.info("a")
        log.info("b")
        log.info("c")

        // All three entries land, but they share one throttled signal task.
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
        let log = events.logger(for: .file, connectionId: UUID())

        #expect(!events.isActive)

        log.info("f")
        await waitUntil { events.isActive && clock.pendingCount == 1 }
        #expect(events.isActive)

        // Draining the throttle clears isActive even though entries remain.
        clock.advance(by: .milliseconds(250))
        await waitUntil { !events.isActive }
        #expect(!events.isActive)
        #expect(events.value.count == 1)
    }
}
