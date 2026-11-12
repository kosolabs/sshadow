import Foundation
import SwiftData

@testable import CoreKit

package func makeEventStore() throws -> ModelContainer {
    try AppDB.getModelContainer(
        config: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

extension ModelContainer {
    @MainActor
    package var savedEvents: [Event] {
        let oldestFirst = FetchDescriptor<EventModel>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let models = (try? mainContext.fetch(oldestFirst)) ?? []
        return models.compactMap { Event(from: $0) }
    }
}
