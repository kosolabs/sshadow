import Common
import FileProvider
import Foundation
import SwiftData

private let logger = Logger(category: "AppDB")

@ModelActor
public actor AppDB {
    public static let shared: AppDB = try! open()

    public static func getModelContainer(
        config: ModelConfiguration = ModelConfiguration(
            groupContainer: .identifier(SSHadow.appGroup)
        )
    ) throws -> ModelContainer {
        let schema = Schema([ConnectionConfigModel.self])
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

    public func enabledConfigs() -> [ConnectionConfig] {
        let descriptor = FetchDescriptor<ConnectionConfigModel>(
            predicate: #Predicate { profile in
                profile.enabled
            }
        )
        guard let profiles = try? modelContext.fetch(descriptor) else {
            return []
        }
        return profiles.compactMap { try? ConnectionConfig(from: $0) }
    }
}
