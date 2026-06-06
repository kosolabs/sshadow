import Common
import FileProvider
import Foundation
import SwiftData

private let logger = Logger(category: "DomainDB")

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
            throw AgentError.itemNotFound(id)
        }
        return item.name
    }

    func child(
        of parent: NSFileProviderItemIdentifier = .rootContainer,
        name: String
    ) throws -> NSFileProviderItemIdentifier {
        guard let item = fetch(parentId: parent, name: name) else {
            throw AgentError.itemNotFound
        }
        return item.id
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
            throw AgentError.itemNotFound(id)
        }
        return item.parentId
    }

    func path(for id: NSFileProviderItemIdentifier) throws -> String {
        var current = id
        var segments: [String] = []

        while current != .rootContainer, current != .workingSet {
            guard let item = fetch(id: current) else {
                throw AgentError.itemNotFound(current)
            }
            segments.append(item.name)
            current = item.parentId
        }

        return segments.reversed().joined(separator: "/")
    }

    func path(
        for name: String,
        in parentId: NSFileProviderItemIdentifier
    ) throws -> String {
        let parentPath = try path(for: parentId)
        return parentPath.isEmpty ? name : parentPath + "/" + name
    }

    func move(
        _ id: NSFileProviderItemIdentifier,
        toParent newParentId: NSFileProviderItemIdentifier,
        name newName: String
    ) throws {
        guard let item = fetch(id: id) else {
            throw AgentError.itemNotFound(id)
        }
        item.parentId = newParentId
        item.name = newName
        try modelContext.save()
    }

    func remove(_ id: NSFileProviderItemIdentifier) throws {
        guard let item = fetch(id: id) else {
            throw AgentError.itemNotFound(id)
        }
        
        if item.kind == .folder {
            for child in children(of: id) {
                try remove(child.id)
            }
        }

        modelContext.delete(item)
    }

    func setAttributes(
        for id: NSFileProviderItemIdentifier,
        permissions: mode_t? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil
    ) throws {
        guard let item = fetch(id: id) else {
            throw AgentError.itemNotFound
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
        parentId: NSFileProviderItemIdentifier = .rootContainer,
        name: String,
        kind: ItemModel.Kind,
        size: UInt64? = nil,
        permissions: UInt32? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil,
        createTime: Date? = nil
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
