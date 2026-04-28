import FileProvider
import Foundation
import SwiftData

private let logger = Logger(category: "DomainDB")

@ModelActor
public actor DomainDB {
    public static var urlFactory: (UUID) -> URL = { id in
        SSHadow.groupUrl.appendingPathComponent(
            "DomainDB-\(id.uuidString).store"
        )
    }

    @discardableResult
    public static func open(id: UUID) async throws -> DomainDB {
        let schema = Schema([PathNode.self, FileChunk.self])

        let db = try DomainDB(
            modelContainer: ModelContainer(
                for: schema,
                configurations: ModelConfiguration(url: urlFactory(id))
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
                id: .trashContainer,
                parentId: .rootContainer,
                name: ".Trashes"
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
        let basePath = urlFactory(id).path

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

    public enum OnNotExists: Codable {
        case fail
        case create
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
            throw NSFileProviderError(.noSuchItem)
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
            throw NSFileProviderError(.noSuchItem)
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

    // MARK: - Chunk Cache

    public func isChunkCached(
        for itemId: NSFileProviderItemIdentifier,
        index: UInt64
    ) -> Bool {
        let rawItemId = itemId.rawValue
        let descriptor = FetchDescriptor<FileChunk>(
            predicate: #Predicate { chunk in
                chunk.rawItemId == rawItemId && chunk.index == index
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    public func recordChunk(
        for itemId: NSFileProviderItemIdentifier,
        index: UInt64
    ) throws {
        guard !isChunkCached(for: itemId, index: index) else { return }
        modelContext.insert(FileChunk(itemId: itemId, index: index))
        try modelContext.save()
    }

    public func deleteChunks(
        for itemId: NSFileProviderItemIdentifier
    ) throws {
        let rawItemId = itemId.rawValue
        try modelContext.delete(
            model: FileChunk.self,
            where: #Predicate { chunk in
                chunk.rawItemId == rawItemId
            }
        )
        try modelContext.save()
    }
}
