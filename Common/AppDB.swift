import FileProvider
import Foundation
import SwiftData

private let logger = Logger(category: "AppDB")

@ModelActor
public actor AppDB {
    public static func getModelContainer(
        config: ModelConfiguration = ModelConfiguration(
            groupContainer: .identifier(SSHadow.appGroup)
        )
    ) throws -> ModelContainer {
        let schema = Schema([ConnectionProfile.self])
        return try ModelContainer(
            for: schema,
            configurations: config
        )
    }
    public static func open(
        config: ModelConfiguration = ModelConfiguration(
            groupContainer: .identifier(SSHadow.appGroup)
        )
    ) throws -> AppDB {
        return try AppDB(modelContainer: getModelContainer(config: config))
    }

    public func fetch(id: UUID) -> ConnectionProfile? {
        let descriptor = FetchDescriptor<ConnectionProfile>(
            predicate: #Predicate { profile in
                profile.id == id
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    public func upsert(profile: ConnectionProfile) throws {
        modelContext.insert(profile)
        try modelContext.save()
    }
}
