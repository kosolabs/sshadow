import Foundation

public struct EventFilter {
    public var hiddenLevels: Set<Event.Level> = []
    public var hiddenCategories: Set<Event.Category> = []

    public init() {}

    public func includes(_ event: Event, matching search: String) -> Bool {
        guard
            !hiddenLevels.contains(event.level),
            !hiddenCategories.contains(event.category)
        else { return false }

        let search = search.trimmingCharacters(in: .whitespaces)
        guard !search.isEmpty else { return true }
        return [event.message, event.detail, event.source?.name]
            .compactMap { $0 }
            .contains { $0.localizedStandardContains(search) }
    }
}
