import Common
import Foundation
import SwiftData
import Testing

@testable import CoreKit

@MainActor
struct EventsTests {
    private struct SampleError: LocalizedError {
        var errorDescription: String? { "something went wrong" }
    }

    private let source = Event.Source(name: "test", url: "user@host")

    @Test func loggerStoresEntryWithInstantAndFields() async {
        let events = Events(clock: TestClock())
        let log = events.logger(for: .file, source: source)

        let before = Date.now
        log.info("Upload /f", detail: "ok")
        await expect(eventually: { events.value.count == 1 })
        let after = Date.now

        let event = events.value[0]
        #expect(event.message == "Upload /f")
        #expect(event.level == .info)
        #expect(event.category == .file)
        #expect(event.detail == "ok")
        #expect(event.source == source)
        // `timestamp` is a wall-clock timestamp, stamped independently of the
        // injected (sleep-only) clock.
        #expect(event.timestamp >= before)
        #expect(event.timestamp <= after)
    }

    @Test func loggerMapsEachMethodOntoItsLevel() async {
        let events = Events(clock: TestClock())
        let log = events.logger(for: .connection, source: source)

        log.info("a")
        log.notice("b")
        log.warning("c")
        log.error("d")

        await expect(eventually: { events.value.count == 4 })

        #expect(
            events.value.map(\.level) == [.info, .notice, .warning, .error]
        )
    }

    @Test func loggerRecordsErrorDescriptionAsDetail() async {
        let events = Events(clock: TestClock())
        let log = events.logger(for: .connection, source: source)

        log.warning("Reconnecting", error: SampleError())
        log.error("Failed", error: SampleError())

        await expect(eventually: { events.value.count == 2 })

        #expect(events.value[0].level == .warning)
        #expect(events.value[0].detail == "something went wrong")
        #expect(events.value[1].level == .error)
        #expect(events.value[1].detail == "something went wrong")
    }

    @Test func loggerCarriesItsCategoryAndConfig() async {
        let events = Events(clock: TestClock())

        let syncSource = Event.Source(name: "sync", url: "")
        let fileSource = Event.Source(name: "file", url: "")

        let syncLog = events.logger(for: .sync, source: syncSource)
        let fileLog = events.logger(for: .file, source: fileSource)

        syncLog.notice("synced")
        fileLog.info("downloaded")

        await expect(eventually: { events.value.count == 2 })

        #expect(events.value[0].category == .sync)
        #expect(events.value[0].source == syncSource)
        #expect(events.value[1].category == .file)
        #expect(events.value[1].source == fileSource)
    }

    @Test func logsPreserveOrder() async {
        let events = Events(clock: TestClock())
        let log = events.logger(for: .file, source: source)

        log.info("a")
        log.info("b")
        log.info("c")

        await expect(eventually: { events.value.count == 3 })

        #expect(events.value.map(\.message) == ["a", "b", "c"])
    }

    @Test func clearRemovesAllEntries() async {
        let events = Events(clock: TestClock())
        let log = events.logger(for: .file, source: source)

        log.info("a")
        log.info("b")
        await expect(eventually: { events.value.count == 2 })

        events.clear()

        #expect(events.value.isEmpty)
    }

    @Test func rapidLogsCoalesceIntoASingleSignalUpdate() async {
        let clock = TestClock()
        let events = Events(clock: clock)
        let log = events.logger(for: .file, source: source)

        log.info("a")
        log.info("b")
        log.info("c")

        // All three entries land, but they share one throttled signal task.
        await expect(eventually: {
            events.value.count == 3 && clock.pendingCount == 1
        })

        #expect(events.isActive)

        // Drain the parked sleep so no continuation is left suspended.
        clock.advance(by: .milliseconds(250))
        await expect(eventually: { !events.isActive })
    }

    @Test func isActiveDependsOnlyOnThePendingSignalTask() async {
        let clock = TestClock()
        let events = Events(clock: clock)
        let log = events.logger(for: .file, source: source)

        #expect(!events.isActive)

        log.info("f")
        await expect(eventually: {
            events.isActive && clock.pendingCount == 1
        })

        // Draining the throttle clears isActive even though entries remain.
        clock.advance(by: .milliseconds(250))
        await expect(eventually: { !events.isActive })
        #expect(events.value.count == 1)
    }

    // MARK: - Persistence

    private func openStore() throws -> ModelContainer {
        try AppDB.getModelContainer(
            config: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func saved(in store: ModelContainer) -> [Event] {
        let oldestFirst = FetchDescriptor<EventModel>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let models = (try? store.mainContext.fetch(oldestFirst)) ?? []
        return models.compactMap { Event(from: $0) }
    }

    private func flush(_ clock: TestClock) async {
        await expect(eventually: { clock.pendingCount == 1 })
        clock.advance(by: .milliseconds(250))
    }

    @Test func savedEventsAreLoadedAtTheNextLaunch() async throws {
        let store = try openStore()
        let clock = TestClock()
        let events = Events(clock: clock)
        events.persist(in: store)
        let log = events.logger(for: .file, source: source)

        log.info("a")
        log.warning("b", detail: "why")
        await flush(clock)
        await expect(eventually: { saved(in: store).count == 2 })

        let relaunched = Events(clock: TestClock())
        relaunched.persist(in: store)

        #expect(relaunched.value.map(\.id) == events.value.map(\.id))
        #expect(relaunched.value[1].level == .warning)
        #expect(relaunched.value[1].detail == "why")
        #expect(relaunched.value[1].source == source)
    }

    @Test func eventsLoggedBeforePersistingAreSaved() async throws {
        let store = try openStore()
        let clock = TestClock()
        let events = Events(clock: clock)
        let log = events.logger(for: .file, source: source)

        log.info("early")
        await flush(clock)
        await expect(eventually: { !events.isActive })
        events.persist(in: store)

        #expect(saved(in: store).map(\.message) == ["early"])
    }

    @Test func clearRemovesSavedEvents() async throws {
        let store = try openStore()
        let clock = TestClock()
        let events = Events(clock: clock)
        events.persist(in: store)
        let log = events.logger(for: .file, source: source)

        log.info("a")
        await flush(clock)
        await expect(eventually: { saved(in: store).count == 1 })
        events.clear()

        #expect(saved(in: store).isEmpty)
    }
}
