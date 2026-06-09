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
                name: ""
            )
        )
        try upsert(
            ItemModel(
                id: .trashContainer,
                name: ".sshadow/trash"
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

    func item(for id: NSFileProviderItemIdentifier) throws -> Item {
        return try Item(from: model(for: id))
    }

    func name(of id: NSFileProviderItemIdentifier) throws -> String {
        try model(for: id).name
    }

    func children(of id: NSFileProviderItemIdentifier) throws -> [Item] {
        try model(for: id).children.map { Item(from: $0) }
    }

    func child(
        of parentId: NSFileProviderItemIdentifier = .rootContainer,
        name: String
    ) throws -> Item {
        let parent = try model(for: parentId)
        if let child = parent.child(named: name) {
            return Item(from: child)
        }
        throw AgentError.itemNotFound
    }

    func parent(of id: NSFileProviderItemIdentifier) throws -> Item {
        if let parent = try model(for: id).parent {
            return Item(from: parent)
        }
        throw AgentError.itemNotFound
    }

    func path(for id: NSFileProviderItemIdentifier) throws -> String {
        try sequence(first: model(for: id), next: \.parent)
            .prefix(while: { $0.id != .rootContainer })
            .map(\.name)
            .reversed()
            .joined(separator: "/")
    }

    func path(
        for name: String,
        in parentId: NSFileProviderItemIdentifier
    ) throws -> String {
        let parentPath = try path(for: parentId)
        return [parentPath, name].filter { !$0.isEmpty }.joined(separator: "/")
    }

    func move(
        _ id: NSFileProviderItemIdentifier,
        toParent parentId: NSFileProviderItemIdentifier,
        name newName: String
    ) throws {
        let item = try model(for: id)
        item.parent = try model(for: parentId)
        item.name = newName
        try modelContext.save()
    }

    func remove(_ id: NSFileProviderItemIdentifier) throws {
        try modelContext.delete(model(for: id))
        try modelContext.save()
    }

    func setAttributes(
        for id: NSFileProviderItemIdentifier,
        permissions: mode_t? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil
    ) throws {
        let item = try model(for: id)
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

    func isEnumerated(_ id: NSFileProviderItemIdentifier) throws -> Bool {
        try model(for: id).enumeratedAt != nil
    }

    func markEnumerated(
        _ id: NSFileProviderItemIdentifier,
        at date: Date = Date()
    ) throws {
        let item = try model(for: id)
        item.enumeratedAt = date
        try modelContext.save()
    }

    func refresh(
        _ id: NSFileProviderItemIdentifier,
        size: UInt64?,
        permissions: UInt32?,
        accessTime: Date?,
        modifyTime: Date?,
        createTime: Date?
    ) throws {
        let item = try model(for: id)
        item.size = size
        item.permissions = permissions
        item.accessTime = accessTime
        item.modifyTime = modifyTime
        item.createTime = createTime
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
    ) throws -> Item {
        try Item(
            from: upsert(
                parent: model(for: parentId),
                name: name,
                kind: kind,
                size: size,
                permissions: permissions,
                accessTime: accessTime,
                modifyTime: modifyTime,
                createTime: createTime
            )
        )
    }

    private func model(
        for id: NSFileProviderItemIdentifier
    ) throws -> ItemModel {
        let rawId = id.rawValue
        let descriptor = FetchDescriptor<ItemModel>(
            predicate: #Predicate { row in
                row.rawId == rawId
            }
        )
        if let model = try modelContext.fetch(descriptor).first {
            return model
        }
        throw AgentError.itemNotFound(id)
    }

    @discardableResult
    private func upsert(
        parent: ItemModel,
        name: String,
        kind: ItemModel.Kind,
        size: UInt64? = nil,
        permissions: UInt32? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil,
        createTime: Date? = nil
    ) throws -> ItemModel {
        let item: ItemModel
        if let child = parent.child(named: name) {
            item = child
        } else {
            item = ItemModel(parent: parent, name: name)
            modelContext.insert(item)
        }
        item.kind = kind
        item.size = size
        item.permissions = permissions
        item.accessTime = accessTime
        item.modifyTime = modifyTime
        item.createTime = createTime
        try modelContext.save()
        return item
    }

    @discardableResult
    private func upsert(_ item: ItemModel) throws -> ItemModel {
        modelContext.insert(item)
        try modelContext.save()
        return item
    }
}
