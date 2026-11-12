import Common
import Foundation
import SwiftData
import TestKit
import Testing

@testable import CoreKit

@MainActor
struct EventsTests {
    private struct SampleError: LocalizedError {
        var errorDescription: String? { "something went wrong" }
    }

    private let source = Event.Source(name: "test", url: "user@host")

    @Test func loggerStoresEntryWithInstantAndFields() async throws {
        let (events, clock, store) = try attached()
        let log = events.logger(for: .file, source: source)

        let before = Date.now
        log.info("Upload /f", detail: "ok")
        let after = Date.now

        let event = try #require(await saved(1, in: store, advancing: clock).first)
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

    @Test func loggerMapsEachMethodOntoItsLevel() async throws {
        let (events, clock, store) = try attached()
        let log = events.logger(for: .connection, source: source)

        log.info("a")
        log.notice("b")
        log.warning("c")
        log.error("d")

        #expect(
            await saved(4, in: store, advancing: clock).map(\.level)
                == [.info, .notice, .warning, .error]
        )
    }

    @Test func loggerRecordsErrorDescriptionAsDetail() async throws {
        let (events, clock, store) = try attached()
        let log = events.logger(for: .connection, source: source)

        log.warning("Reconnecting", error: SampleError())
        log.error("Failed", error: SampleError())

        let saved = await saved(2, in: store, advancing: clock)
        #expect(saved[0].level == .warning)
        #expect(saved[0].detail == "something went wrong")
        #expect(saved[1].level == .error)
        #expect(saved[1].detail == "something went wrong")
    }

    @Test func loggerCarriesItsCategoryAndConfig() async throws {
        let (events, clock, store) = try attached()

        let syncSource = Event.Source(name: "sync", url: "")
        let fileSource = Event.Source(name: "file", url: "")

        let syncLog = events.logger(for: .sync, source: syncSource)
        let fileLog = events.logger(for: .file, source: fileSource)

        syncLog.notice("synced")
        fileLog.info("downloaded")

        let saved = await saved(2, in: store, advancing: clock)
        #expect(saved[0].category == .sync)
        #expect(saved[0].source == syncSource)
        #expect(saved[1].category == .file)
        #expect(saved[1].source == fileSource)
    }

    @Test func logsPreserveOrder() async throws {
        let (events, clock, store) = try attached()
        let log = events.logger(for: .file, source: source)

        log.info("a")
        log.info("b")
        log.info("c")

        #expect(
            await saved(3, in: store, advancing: clock).map(\.message)
                == ["a", "b", "c"]
        )
    }

    @Test func clearRemovesAllEntries() async throws {
        let (events, clock, store) = try attached()
        let log = events.logger(for: .file, source: source)

        log.info("a")
        log.info("b")
        _ = await saved(2, in: store, advancing: clock)

        events.clear()

        #expect(store.savedEvents.isEmpty)
    }

    @Test func rapidLogsCoalesceIntoASingleSignalUpdate() async throws {
        let (events, clock, store) = try attached()
        let log = events.logger(for: .file, source: source)

        log.info("a")
        log.info("b")
        log.info("c")

        // All three entries are pending, but they share one throttled signal
        // task, so they're saved together once it fires.
        await expect(eventually: { clock.pendingCount == 1 })
        #expect(events.isActive)
        #expect(store.savedEvents.isEmpty)

        clock.advance(by: .milliseconds(250))
        await expect(eventually: { !events.isActive })
        #expect(store.savedEvents.count == 3)
    }

    @Test func isActiveDependsOnlyOnThePendingSignalTask() async throws {
        let (events, clock, _) = try attached()
        let log = events.logger(for: .file, source: source)

        #expect(!events.isActive)

        log.info("f")
        await expect(eventually: {
            events.isActive && clock.pendingCount == 1
        })

        clock.advance(by: .milliseconds(250))
        await expect(eventually: { !events.isActive })
    }

    @Test func eventsLoggedBeforePersistingAreSaved() async throws {
        let store = try makeEventStore()
        let clock = TestClock()
        let events = Events(clock: clock)
        let log = events.logger(for: .file, source: source)

        log.info("early")
        await expect(eventually: { clock.pendingCount == 1 })
        clock.advance(by: .milliseconds(250))
        await expect(eventually: { !events.isActive })
        events.persist(in: store)

        #expect(store.savedEvents.map(\.message) == ["early"])
    }

    // MARK: - Helpers

    private func attached() throws -> (Events<TestClock>, TestClock, ModelContainer) {
        let store = try makeEventStore()
        let clock = TestClock()
        let events = Events(clock: clock)
        events.persist(in: store)
        return (events, clock, store)
    }

    private func saved(
        _ count: Int,
        in store: ModelContainer,
        advancing clock: TestClock
    ) async -> [Event] {
        await expect(eventually: {
            clock.advance(by: .milliseconds(250))
            return store.savedEvents.count >= count
        })
        return store.savedEvents
    }
}
