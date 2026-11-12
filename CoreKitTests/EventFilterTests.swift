import Common
import Foundation
import SwiftData
import Testing

@testable import CoreKit

private func event(
    level: Event.Level = .info,
    category: Event.Category = .file,
    message: String = "Upload \"a.txt\"",
    detail: String? = nil,
    source: Event.Source? = Event.Source(name: "Work", url: "me@host")
) -> Event {
    Event(
        timestamp: .now,
        source: source,
        level: level,
        category: category,
        message: message,
        detail: detail
    )
}

private func shows(
    _ event: Event,
    with filter: EventFilter,
    matching search: String
) throws -> Bool {
    let context = try ModelContext(
        AppDB.getModelContainer(
            config: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    )
    context.insert(EventModel(from: event))
    return try !context.fetch(filter.descriptor(matching: search)).isEmpty
}

struct EventFilterTests {
    @Test func defaultShowsEveryLevel() throws {
        for level in Event.Level.allCases {
            #expect(try shows(event(level: level), with: EventFilter(), matching: ""))
        }
    }

    @Test func hiddenLevelIsExcluded() throws {
        var filter = EventFilter()
        filter.hiddenLevels = [.info]
        #expect(try !shows(event(level: .info), with: filter, matching: ""))
        #expect(try shows(event(level: .notice), with: filter, matching: ""))
    }

    @Test func hiddenCategoryIsExcluded() throws {
        var filter = EventFilter()
        filter.hiddenCategories = [.sync]
        #expect(try !shows(event(category: .sync), with: filter, matching: ""))
        #expect(try shows(event(category: .file), with: filter, matching: ""))
    }

    @Test func searchMatchesMessageIgnoringCase() throws {
        #expect(try shows(event(), with: EventFilter(), matching: "A.TXT"))
    }

    @Test func searchMatchesDetail() throws {
        let detail = event(message: "Detected", detail: "dir/report.pdf")
        #expect(try shows(detail, with: EventFilter(), matching: "report"))
    }

    @Test func searchMatchesConnectionName() throws {
        #expect(try shows(event(), with: EventFilter(), matching: "work"))
    }

    @Test func searchExcludesNonMatches() throws {
        #expect(try !shows(event(), with: EventFilter(), matching: "missing"))
    }

    @Test func blankSearchMatchesEverything() throws {
        #expect(try shows(event(), with: EventFilter(), matching: "  "))
    }

    @Test func searchStillRespectsHiddenLevels() throws {
        var filter = EventFilter()
        filter.hiddenLevels = [.info]
        #expect(try !shows(event(level: .info), with: filter, matching: "a"))
    }
}
