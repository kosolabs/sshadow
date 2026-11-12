import Foundation
import SwiftData

public struct EventFilter {
    public var hiddenLevels: Set<Event.Level> = []
    public var hiddenCategories: Set<Event.Category> = []

    public init() {}

    public func descriptor(matching search: String) -> FetchDescriptor<EventModel> {
        let hiddenLevels = hiddenLevels.map(\.rawValue)
        let hiddenCategories = hiddenCategories.map(\.rawValue)
        let search = search.trimmingCharacters(in: .whitespaces)
        let predicate = #Predicate<EventModel> { event in
            !hiddenLevels.contains(event.level)
                && !hiddenCategories.contains(event.category)
                && (search.isEmpty
                    || event.message.localizedStandardContains(search)
                    || event.detail?.localizedStandardContains(search) == true
                    || event.sourceName?.localizedStandardContains(search) == true)
        }
        return FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
    }
}
