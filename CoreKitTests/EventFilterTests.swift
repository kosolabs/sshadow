import Common
import Foundation
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

struct EventFilterTests {
    @Test func defaultShowsEveryLevel() {
        for level in Event.Level.allCases {
            #expect(EventFilter().includes(event(level: level), matching: ""))
        }
    }

    @Test func hiddenLevelIsExcluded() {
        var filter = EventFilter()
        filter.hiddenLevels = [.info]
        #expect(!filter.includes(event(level: .info), matching: ""))
        #expect(filter.includes(event(level: .notice), matching: ""))
    }

    @Test func hiddenCategoryIsExcluded() {
        var filter = EventFilter()
        filter.hiddenCategories = [.sync]
        #expect(!filter.includes(event(category: .sync), matching: ""))
        #expect(filter.includes(event(category: .file), matching: ""))
    }

    @Test func searchMatchesMessageIgnoringCase() {
        #expect(EventFilter().includes(event(), matching: "A.TXT"))
    }

    @Test func searchMatchesDetail() {
        let detail = event(message: "Detected", detail: "dir/report.pdf")
        #expect(EventFilter().includes(detail, matching: "report"))
    }

    @Test func searchMatchesConnectionName() {
        #expect(EventFilter().includes(event(), matching: "work"))
    }

    @Test func searchExcludesNonMatches() {
        #expect(!EventFilter().includes(event(), matching: "missing"))
    }

    @Test func blankSearchMatchesEverything() {
        #expect(EventFilter().includes(event(), matching: "  "))
    }

    @Test func searchStillRespectsHiddenLevels() {
        var filter = EventFilter()
        filter.hiddenLevels = [.info]
        #expect(!filter.includes(event(level: .info), matching: "a"))
    }
}
