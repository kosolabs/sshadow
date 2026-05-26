import Common
import FileProvider
import Foundation
import SwiftData

private let logger = Logger(category: "DomainDB")

@ModelActor
public actor DomainDB {
    private static func url(for id: UUID) -> URL {
        SSHadow.groupUrl.appendingPathComponent(
            "DomainDB-\(id.uuidString).store"
        )
    }

    public static func model(for id: UUID) -> ModelConfiguration {
        ModelConfiguration(url: url(for: id))
    }

    @discardableResult
    public static func open(
        config: ModelConfiguration
    ) async throws -> DomainDB {
        let schema = Schema([PathNode.self])
        if !config.isStoredInMemoryOnly {
            logger.info("Open DomainDB: \(config.url.path)")
        }

        let db = try DomainDB(
            modelContainer: ModelContainer(
                for: schema,
                configurations: config
            )
        )
        try await db.configure()
        return db
    }

    private func configure() throws {
        try upsert(
            PathNode(
                id: .rootContainer,
                parentId: .rootContainer,
                name: ""
            )
        )
        try upsert(
            PathNode(
                id: .sshadowContainer,
                parentId: .rootContainer,
                name: ".sshadow"
            )
        )
        try upsert(
            PathNode(
                id: .trashContainer,
                parentId: .sshadowContainer,
                name: "trash"
            )
        )
        try upsert(
            PathNode(
                id: .workingSet,
                parentId: .rootContainer,
                name: ""
            )
        )
    }

    public static func delete(id: UUID) async throws {
        let basePath = url(for: id).path

        for suffix in ["", "-shm", "-wal"] {
            let path = basePath + suffix
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        }
    }

    public func fetch(id: NSFileProviderItemIdentifier) -> PathNode? {
        let rawId = id.rawValue
        let descriptor = FetchDescriptor<PathNode>(
            predicate: #Predicate { row in
                row.rawId == rawId
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    public func fetch(
        parentId: NSFileProviderItemIdentifier,
        name: String
    ) -> PathNode? {
        let rawParentId = parentId.rawValue
        let descriptor = FetchDescriptor<PathNode>(
            predicate: #Predicate { row in
                row.rawParentId == rawParentId && row.name == name
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    public func name(of id: NSFileProviderItemIdentifier) throws -> String {
        guard let item = fetch(id: id) else {
            throw NSFileProviderError(.noSuchItem)
        }
        return item.name
    }

    private func child(
        of parent: NSFileProviderItemIdentifier,
        name: String,
        ifNotExists: OnNotExists,
    ) throws -> NSFileProviderItemIdentifier {
        if let item = fetch(parentId: parent, name: name) {
            return item.id
        }

        if ifNotExists == .fail {
            throw AgentError.itemNotFound(parent.rawValue)
        }

        let item = PathNode(parentId: parent, name: name)
        try upsert(item)
        return item.id
    }

    public func child(
        of parent: NSFileProviderItemIdentifier = .rootContainer,
        path: String,
        ifNotExists: OnNotExists = .create,
    ) throws -> NSFileProviderItemIdentifier {
        var current = parent
        for segment in path.split(separator: "/").map(String.init) {
            current = try child(
                of: current,
                name: segment,
                ifNotExists: ifNotExists
            )
        }
        return current
    }

    public func parent(
        of id: NSFileProviderItemIdentifier
    ) throws -> NSFileProviderItemIdentifier {
        guard let item = fetch(id: id) else {
            logger.error("Parent not found for item: \(id.rawValue)")
            throw AgentError.itemNotFound(id.rawValue)
        }
        return item.parentId
    }

    public func path(for id: NSFileProviderItemIdentifier) -> String {
        var current = id
        var segments: [String] = []

        while let item = fetch(id: current),
            current != .rootContainer,
            current != .workingSet
        {
            segments.append(item.name)
            current = item.parentId
        }

        return segments.reversed().joined(separator: "/")
    }

    public func path(
        for name: String,
        in parentId: NSFileProviderItemIdentifier
    ) -> String {
        let parentPath = path(for: parentId)
        return parentPath.isEmpty ? name : parentPath + "/" + name
    }

    public func move(
        _ id: NSFileProviderItemIdentifier,
        toParent newParentId: NSFileProviderItemIdentifier,
        name newName: String
    ) throws {
        guard let item = fetch(id: id) else {
            throw NSFileProviderError(.noSuchItem)
        }
        item.parentId = newParentId
        item.name = newName
        try modelContext.save()
    }

    public func upsert(_ item: PathNode) throws {
        modelContext.insert(item)
        try modelContext.save()
    }

}
