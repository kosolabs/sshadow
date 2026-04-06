import FileProvider
import Foundation
import SwiftData

@ModelActor
public actor SSHadowDB {
    public static func open(domain: NSFileProviderDomain) throws -> SSHadowDB {
        let schema = Schema([SSHItem.self])
        let groupURL = try SSHadow.groupURL()

        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                url: groupURL.appendingPathComponent(
                    "SSHadowDB-\(domain.identifier.rawValue).sqlite"
                )
            )
        )

        return SSHadowDB(modelContainer: container)
    }

    public static func create(domain: NSFileProviderDomain) async throws {
        let db = try SSHadowDB.open(domain: domain)
        try await db.seed()
    }

    public func seed() throws {
        let rootId = NSFileProviderItemIdentifier.rootContainer.rawValue
        let trashId = NSFileProviderItemIdentifier.trashContainer.rawValue
        let workingSetId = NSFileProviderItemIdentifier.workingSet.rawValue

        try upsert(SSHItem(id: rootId, parentId: rootId, name: ""))
        try upsert(SSHItem(id: trashId, parentId: rootId, name: ".Trashes"))
        try upsert(SSHItem(id: workingSetId, parentId: rootId, name: ""))
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
            predicate: #Predicate { row in
                row.id == id
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    public func fetch(parentId: String, name: String) -> SSHItem? {
        let descriptor = FetchDescriptor<SSHItem>(
            predicate: #Predicate { row in
                row.parentId == parentId && row.name == name
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    public func upsert(_ item: SSHItem) throws {
        modelContext.insert(item)
        try modelContext.save()
    }
}
