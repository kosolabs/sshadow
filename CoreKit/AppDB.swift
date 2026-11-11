import Common
import FileProvider
import Foundation
import SwiftData

private let logger = Logger(category: "AppDB")

@ModelActor
public actor AppDB {
    public static let shared: AppDB = try! open()

    public static func getModelContainer(
        config: ModelConfiguration = ModelConfiguration()
    ) throws -> ModelContainer {
        let schema = Schema([
            ConnectionConfigModel.self, SettingsModel.self, EventModel.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: config
        )
    }

    public static func open(
        config: ModelConfiguration = ModelConfiguration()
    ) throws -> AppDB {
        return try AppDB(modelContainer: getModelContainer(config: config))
    }

    public func enabledIds() -> Set<UUID>? {
        let descriptor = FetchDescriptor<ConnectionConfigModel>(
            predicate: #Predicate { profile in
                profile.enabled
            }
        )
        guard let profiles = try? modelContext.fetch(descriptor) else {
            return nil
        }
        return Set(profiles.map(\.id))
    }
}

// MARK: - Events

extension AppDB {
    func append(_ events: [Event]) throws {
        for event in events {
            modelContext.insert(EventModel(from: event))
        }
        try modelContext.save()
    }

    func newestEvents(limit: Int) throws -> [Event] {
        var descriptor = FetchDescriptor<EventModel>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).reversed().compactMap {
            Event(from: $0)
        }
    }

    func removeAllEvents() throws {
        try modelContext.delete(model: EventModel.self)
        try modelContext.save()
    }
}
