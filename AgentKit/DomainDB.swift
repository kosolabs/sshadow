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

    func fetch(id: NSFileProviderItemIdentifier) -> ItemModel? {
        let rawId = id.rawValue
        let descriptor = FetchDescriptor<ItemModel>(
            predicate: #Predicate { row in
                row.rawId == rawId
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func item(for id: NSFileProviderItemIdentifier) throws -> ItemModel {
        if let item = fetch(id: id) { return item }
        throw AgentError.itemNotFound(id)
    }

    func name(of id: NSFileProviderItemIdentifier) throws -> String {
        try item(for: id).name
    }

    func child(
        of parentId: NSFileProviderItemIdentifier = .rootContainer,
        name: String
    ) throws -> ItemModel {
        let parent = try item(for: parentId)
        if let child = parent.child(named: name) {
            return child
        }
        throw AgentError.itemNotFound
    }

    func parent(of id: NSFileProviderItemIdentifier) throws -> ItemModel {
        if let parent = try item(for: id).parent {
            return parent
        }
        throw AgentError.itemNotFound
    }

    func path(for id: NSFileProviderItemIdentifier) throws -> String {
        try sequence(first: item(for: id), next: \.parent)
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
        let model = try item(for: id)
        model.parent = try item(for: parentId)
        model.name = newName
        try modelContext.save()
    }

    func remove(_ id: NSFileProviderItemIdentifier) throws {
        try modelContext.delete(item(for: id))
        try modelContext.save()
    }

    func setAttributes(
        for id: NSFileProviderItemIdentifier,
        permissions: mode_t? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil
    ) throws {
        let model = try item(for: id)
        if let permissions = permissions {
            model.permissions = UInt32(permissions)
        }
        if let accessTime = accessTime {
            model.accessTime = accessTime
        }
        if let modifyTime = modifyTime {
            model.modifyTime = modifyTime
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
        let model = try item(for: id)
        model.enumeratedAt = date
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
        let model = try item(for: id)
        model.size = size
        model.permissions = permissions
        model.accessTime = accessTime
        model.modifyTime = modifyTime
        model.createTime = createTime
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
        try upsert(
            parent: item(for: parentId),
            name: name,
            kind: kind,
            size: size,
            permissions: permissions,
            accessTime: accessTime,
            modifyTime: modifyTime,
            createTime: createTime
        )
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
