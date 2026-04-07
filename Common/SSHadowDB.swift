import FileProvider
import Foundation
import SwiftData

@ModelActor
public actor SSHadowDB {
    private var logger = Logger(category: "SSHadowDB")

    public static func open(
        domain: NSFileProviderDomain
    ) async throws -> SSHadowDB {
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

        let db = SSHadowDB(modelContainer: container)
        await db.configure(domain: domain)
        return db
    }

    private func configure(domain: NSFileProviderDomain) {
        logger = Logger(category: "\(domain.displayName):SSHadowDB")
    }

    public static func create(domain: NSFileProviderDomain) async throws {
        let db = try await SSHadowDB.open(domain: domain)
        try await db.seed()
    }

    public func seed() throws {
        try upsert(
            SSHItem(
                id: .rootContainer,
                parentId: .rootContainer,
                name: ""
            )
        )
        try upsert(
            SSHItem(
                id: .trashContainer,
                parentId: .rootContainer,
                name: ".Trashes"
            )
        )
        try upsert(
            SSHItem(
                id: .workingSet,
                parentId: .rootContainer,
                name: ""
            )
        )
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

    public func fetch(id: NSFileProviderItemIdentifier) -> SSHItem? {
        let rawId = id.rawValue
        let descriptor = FetchDescriptor<SSHItem>(
            predicate: #Predicate { row in
                row.rawId == rawId
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    public func fetch(
        parentId: NSFileProviderItemIdentifier,
        name: String
    ) -> SSHItem? {
        let rawParentId = parentId.rawValue
        let descriptor = FetchDescriptor<SSHItem>(
            predicate: #Predicate { row in
                row.rawParentId == rawParentId && row.name == name
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    public func child(
        of parent: NSFileProviderItemIdentifier,
        name: String
    ) throws -> NSFileProviderItemIdentifier {
        if let item = fetch(parentId: parent, name: name) {
            return item.id
        }

        let item = SSHItem(parentId: parent, name: name)
        try upsert(item)
        return item.id
    }

    public func parent(
        of id: NSFileProviderItemIdentifier
    ) throws -> NSFileProviderItemIdentifier {
        guard let item = fetch(id: id) else {
            logger.error("Parent not found for item: \(id.rawValue)")
            throw NSFileProviderError(.noSuchItem)
        }
        return item.parentId
    }

    public func path(
        for id: NSFileProviderItemIdentifier
    ) throws -> String {
        var current = id
        var segments: [String] = []

        while let item = fetch(id: current),
            current != .rootContainer,
            current != .trashContainer,
            current != .workingSet
        {
            segments.append(item.name)
            current = item.parentId
        }

        return segments.reversed().joined(separator: "/")
    }

    public func upsert(_ item: SSHItem) throws {
        modelContext.insert(item)
        try modelContext.save()
    }
}
