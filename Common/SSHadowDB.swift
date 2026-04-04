import FileProvider
import Foundation
import SwiftData

private func defaultModelContainer(for domain: NSFileProviderDomain) throws
    -> ModelContainer
{
    let schema = Schema([SSHItem.self])
    let groupURL = try SSHadow.groupURL()

    return try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(
            schema: schema,
            url: groupURL.appendingPathComponent(
                "SSHadowDB-\(domain.identifier.rawValue).sqlite"
            )
        )
    )
}

@ModelActor
public actor SSHadowDB {
    public init(
        domain: NSFileProviderDomain,
        modelContainer: ModelContainer? = nil
    ) throws {
        self.modelContainer =
            try modelContainer ?? defaultModelContainer(for: domain)
        self.modelExecutor = DefaultSerialModelExecutor(
            modelContext: ModelContext(self.modelContainer)
        )
    }

    public static func create(domain: NSFileProviderDomain) async throws {
        _ = try SSHadowDB(domain: domain)
    }

    public static func delete(domain: NSFileProviderDomain) async throws {
        let groupURL = try SSHadow.groupURL()

        let basePath = groupURL.appendingPathComponent(
            "SSHadowDB-\(domain.identifier.rawValue).sqlite"
        ).path

        for suffix in ["", "-shm", "-wal"] {
            let path = basePath + suffix
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        }
    }

    public func fetch(id: String) -> SSHItem? {
        let descriptor = FetchDescriptor<SSHItem>(
            predicate: #Predicate { input in
                input.id == id
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    public func upsert(_ item: SSHItem) throws {
        modelContext.insert(item)
        try modelContext.save()
    }
}
