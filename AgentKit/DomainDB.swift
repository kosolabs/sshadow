import Common
import FileProvider
import Foundation
import SwiftData

private let logger = Logger(category: "DomainDB")

enum OnNotExists: Codable, PrettyDescribable {
    case fail
    case create
}

@ModelActor
actor DomainDB {
    private static func url(for id: UUID) -> URL {
        SSHadow.groupUrl.appendingPathComponent(
            "DomainDB-\(id.uuidString).store"
        )
    }

    static func model(for id: UUID) -> ModelConfiguration {
        ModelConfiguration(url: url(for: id))
    }

    @discardableResult
    static func open(
        config: ModelConfiguration
    ) async throws -> DomainDB {
        let schema = Schema([ItemModel.self])
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
            ItemModel(
                id: .rootContainer,
                parentId: .rootContainer,
                name: ""
            )
        )
        try upsert(
            ItemModel(
                id: .sshadowContainer,
                parentId: .rootContainer,
                name: ".sshadow"
            )
        )
        try upsert(
            ItemModel(
                id: .trashContainer,
                parentId: .sshadowContainer,
                name: "trash"
            )
        )
        try upsert(
            ItemModel(
                id: .workingSet,
                parentId: .rootContainer,
                name: ""
            )
        )
    }

    static func delete(id: UUID) async throws {
        let basePath = url(for: id).path

        for suffix in ["", "-shm", "-wal"] {
            let path = basePath + suffix
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        }
    }

    func fetch(id: NSFileProviderItemIdentifier) -> ItemModel? {
        let rawId = id.rawValue
        let descriptor = FetchDescriptor<ItemModel>(
            predicate: #Predicate { row in
                row.rawId == rawId
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func fetch(
        parentId: NSFileProviderItemIdentifier,
        name: String
    ) -> ItemModel? {
        let rawParentId = parentId.rawValue
        let descriptor = FetchDescriptor<ItemModel>(
            predicate: #Predicate { row in
                row.rawParentId == rawParentId && row.name == name
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func name(of id: NSFileProviderItemIdentifier) throws -> String {
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

        let item = ItemModel(parentId: parent, name: name)
        try upsert(item)
        return item.id
    }

    func child(
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

    func children(of parentId: NSFileProviderItemIdentifier) -> [ItemModel] {
        let rawParentId = parentId.rawValue
        let descriptor = FetchDescriptor<ItemModel>(
            predicate: #Predicate { row in
                row.rawParentId == rawParentId
                    && row.rawId != rawParentId
                    && row.modifyTime != nil
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func parent(
        of id: NSFileProviderItemIdentifier
    ) throws -> NSFileProviderItemIdentifier {
        guard let item = fetch(id: id) else {
            logger.error("Parent not found for item: \(id.rawValue)")
            throw AgentError.itemNotFound(id.rawValue)
        }
        return item.parentId
    }

    func path(for id: NSFileProviderItemIdentifier) -> String {
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

    func path(
        for name: String,
        in parentId: NSFileProviderItemIdentifier
    ) -> String {
        let parentPath = path(for: parentId)
        return parentPath.isEmpty ? name : parentPath + "/" + name
    }

    func move(
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

    func setAttributes(
        for id: NSFileProviderItemIdentifier,
        permissions: mode_t? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil
    ) throws {
        guard let item = fetch(id: id) else {
            throw NSFileProviderError(.noSuchItem)
        }
        if let permissions = permissions {
            item.permissions = UInt32(permissions)
        }
        if let accessTime = accessTime {
            item.accessTime = accessTime
        }
        if let modifyTime = modifyTime {
            item.modifyTime = modifyTime
        }
        try modelContext.save()
    }

    func isEnumerated(_ id: NSFileProviderItemIdentifier) -> Bool {
        fetch(id: id)?.enumeratedAt != nil
    }

    func markEnumerated(
        _ id: NSFileProviderItemIdentifier,
        at date: Date = Date()
    ) throws {
        guard let item = fetch(id: id) else {
            throw AgentError.itemNotFound(id.rawValue)
        }
        item.enumeratedAt = date
        try modelContext.save()
    }

    func upsert(_ item: ItemModel) throws {
        modelContext.insert(item)
        try modelContext.save()
    }

    @discardableResult
    func upsert(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        kind: ItemModel.Kind,
        size: UInt64?,
        permissions: UInt32?,
        accessTime: Date?,
        modifyTime: Date?,
        createTime: Date?
    ) throws -> ItemModel {
        let item =
            fetch(parentId: parentId, name: name)
            ?? ItemModel(parentId: parentId, name: name)
        item.kind = kind
        item.size = size
        item.permissions = permissions
        item.accessTime = accessTime
        item.modifyTime = modifyTime
        item.createTime = createTime
        modelContext.insert(item)
        try modelContext.save()
        return item
    }
}
