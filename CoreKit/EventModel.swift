import Foundation
import SwiftData

@Model
public final class EventModel {
    #Index<EventModel>([\.timestamp])

    @Attribute(.unique) public var id: UUID
    var timestamp: Date
    var sourceName: String?
    var sourceUrl: String?
    var level: String
    var category: String
    var message: String
    var detail: String?

    init(from event: Event) {
        self.id = event.id
        self.timestamp = event.timestamp
        self.sourceName = event.source?.name
        self.sourceUrl = event.source?.url
        self.level = event.level.rawValue
        self.category = event.category.rawValue
        self.message = event.message
        self.detail = event.detail
    }
}

extension Event {
    public init?(from model: EventModel) {
        guard let level = Level(rawValue: model.level),
            let category = Category(rawValue: model.category)
        else { return nil }
        var source: Source?
        if let name = model.sourceName, let url = model.sourceUrl {
            source = Source(name: name, url: url)
        }
        self.init(
            id: model.id,
            timestamp: model.timestamp,
            source: source,
            level: level,
            category: category,
            message: model.message,
            detail: model.detail
        )
    }
}
