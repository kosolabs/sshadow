import Foundation
import SwiftData
import FileProvider

@Model
public class ItemMapping {
    @Attribute(.unique) public var id: String
    public var parentId: String
    public var name: String

    public init(id: String, parentId: String, name: String) {
        self.id = id
        self.parentId = parentId
        self.name = name
    }
}

@ModelActor
public actor ItemManager {
    public init(domain: NSFileProviderDomain) throws {
        let schema = Schema([ItemMapping.self])
        guard let groupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.kosolabs.SSHadow") else {
            throw CocoaError(.fileReadUnknown)
        }
        
        let storeUrl = groupUrl.appendingPathComponent("DomainDB_\(domain.identifier.rawValue).sqlite")
        let config = ModelConfiguration(schema: schema, url: storeUrl)
        
        // Use the explicit intializer for ModelActor
        let container = try ModelContainer(for: schema, configurations: [config])
        self.modelContainer = container
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(container))
        
        ensureSystemRoots()
    }
    
    private func ensureSystemRoots() {
        let rootId = NSFileProviderItemIdentifier.rootContainer.rawValue
        if fetch(id: rootId) == nil {
            modelContext.insert(ItemMapping(id: rootId, parentId: rootId, name: ""))
        }
        
        let trashId = NSFileProviderItemIdentifier.trashContainer.rawValue
        if fetch(id: trashId) == nil {
            modelContext.insert(ItemMapping(id: trashId, parentId: rootId, name: ".Trashes"))
        }
        
        let workingSetId = NSFileProviderItemIdentifier.workingSet.rawValue
        if fetch(id: workingSetId) == nil {
            modelContext.insert(ItemMapping(id: workingSetId, parentId: rootId, name: ".WorkingSet"))
        }
    }

    private func fetch(id: String) -> ItemMapping? {
        let descriptor = FetchDescriptor<ItemMapping>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }
    
    private func fetch(parentId: String, name: String) -> ItemMapping? {
        let descriptor = FetchDescriptor<ItemMapping>(predicate: #Predicate { $0.parentId == parentId && $0.name == name })
        return try? modelContext.fetch(descriptor).first
    }

    public func id(for parentId: NSFileProviderItemIdentifier, name: String) -> NSFileProviderItemIdentifier {
        let pId = parentId.rawValue
        if let mapping = fetch(parentId: pId, name: name) {
            return NSFileProviderItemIdentifier(rawValue: mapping.id)
        }
        
        let newId = UUID().uuidString
        let mapping = ItemMapping(id: newId, parentId: pId, name: name)
        modelContext.insert(mapping)
        try? modelContext.save()
        
        return NSFileProviderItemIdentifier(rawValue: newId)
    }

    public func name(for id: NSFileProviderItemIdentifier) -> String {
        return fetch(id: id.rawValue)?.name ?? ""
    }

    public func parent(for id: NSFileProviderItemIdentifier) -> NSFileProviderItemIdentifier {
        guard let mapping = fetch(id: id.rawValue) else {
            return .rootContainer
        }
        return NSFileProviderItemIdentifier(rawValue: mapping.parentId)
    }
    
    public func path(for id: NSFileProviderItemIdentifier) -> String {
        var currentId = id.rawValue
        var names: [String] = []
        
        while let mapping = fetch(id: currentId), currentId != NSFileProviderItemIdentifier.rootContainer.rawValue, currentId != NSFileProviderItemIdentifier.trashContainer.rawValue {
            names.append(mapping.name)
            currentId = mapping.parentId
        }
        
        if currentId == NSFileProviderItemIdentifier.trashContainer.rawValue {
            names.append(".Trashes")
        }
        
        return names.reversed().joined(separator: "/")
    }

    public func update(id: NSFileProviderItemIdentifier, newParentId: NSFileProviderItemIdentifier?, newName: String?) {
        guard let mapping = fetch(id: id.rawValue) else { return }
        
        var changed = false
        if let newP = newParentId?.rawValue, mapping.parentId != newP {
            mapping.parentId = newP
            changed = true
        }
        
        if let newN = newName, mapping.name != newN {
            mapping.name = newN
            changed = true
        }
        
        if changed {
            try? modelContext.save()
        }
    }

    public func delete(id: NSFileProviderItemIdentifier) {
        if let mapping = fetch(id: id.rawValue) {
            modelContext.delete(mapping)
            try? modelContext.save()
        }
    }
}
