import Common
import FileProvider
import Foundation
import SwiftData

extension Item {
    init(from item: ItemModel) {
        self.init(
            id: item.rawId,
            parentId: item.parent?.rawId,
            name: item.name,
            kind: item.kind,
            size: item.size,
            flags: item.flags,
            accessTime: item.accessTime,
            modifyTime: item.modifyTime,
            createTime: item.createTime,
            enumeratedAt: item.enumeratedAt
        )
    }
}

@Model
class ItemModel {
    @Attribute(.unique) var rawId: String
    var name: String
    var kind: Item.Kind
    var size: UInt64?
    var flags: Item.Flags?
    var accessTime: Date?
    var modifyTime: Date?
    var createTime: Date?
    var enumeratedAt: Date?
    
    @Relationship(deleteRule: .cascade, inverse: \ItemModel.parent)
    var children: [ItemModel] = []
    
    @Relationship
    var parent: ItemModel?

    init(
        id: NSFileProviderItemIdentifier =
            NSFileProviderItemIdentifier(UUID().uuidString),
        parent: ItemModel? = nil,
        name: String,
        kind: Item.Kind = .folder,
        size: UInt64? = nil,
        flags: Item.Flags? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil,
        createTime: Date? = nil,
        enumeratedAt: Date? = nil
    ) {
        self.rawId = id.rawValue
        self.parent = parent
        self.name = name
        self.kind = kind
        self.size = size
        self.flags = flags
        self.accessTime = accessTime
        self.modifyTime = modifyTime
        self.createTime = createTime
        self.enumeratedAt = enumeratedAt
    }

    var id: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(rawId)
    }
    
    func child(named: String) -> ItemModel? {
        children.first(where: { $0.name == named })
    }
}
