import FileProvider
import Foundation
import SwiftData

@ModelActor
public actor SSHadowDB {
    private var logger = Logger(category: "SSHadowDB")

    @discardableResult
    public static func open(
        domain: NSFileProviderDomain
    ) async throws -> SSHadowDB {
        let userInfo = try UserInfo.fromDictionary(domain.userInfo)

        let schema = Schema([SSHItem.self])
        let groupURL = try SSHadow.groupURL()
        
        let container = if userInfo.testing {
            try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
            )
        } else {
            try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    schema: schema,
                    url: groupURL.appendingPathComponent(
                        "SSHadowDB-\(domain.identifier.rawValue).sqlite"
                    )
                )
            )
        }

        let db = SSHadowDB(modelContainer: container)
        try await db.configure(domain: domain)
        return db
    }

    private func configure(domain: NSFileProviderDomain) throws {
        logger = Logger(category: "\(domain.displayName):SSHadowDB")
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

    public func name(of id: NSFileProviderItemIdentifier) throws -> String {
        guard let item = fetch(id: id) else {
            throw NSFileProviderError(.noSuchItem)
        }
        return item.name
    }

    public enum OnNotExists {
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

        let item = SSHItem(parentId: parent, name: name)
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

    public func upsert(_ item: SSHItem) throws {
        modelContext.insert(item)
        try modelContext.save()
    }
}
