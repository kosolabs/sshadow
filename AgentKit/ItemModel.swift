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
            kind: Item.Kind(from: item.kind),
            size: item.size,
            permissions: item.permissions,
            accessTime: item.accessTime,
            modifyTime: item.modifyTime,
            createTime: item.createTime,
            enumeratedAt: item.enumeratedAt
        )
    }
}

extension Item.Kind {
    init(from kind: ItemModel.Kind) {
        switch kind {
        case .file: self = .file
        case .folder: self = .folder
        case .symlink(let target): self = .symlink(target: target)
        }
    }
}

@Model
class ItemModel {
    enum Kind: Codable, Equatable {
        case file
        case folder
        case symlink(target: String)

        init(from kind: Item.Kind) {
            switch kind {
            case .file: self = .file
            case .folder: self = .folder
            case .symlink(let target): self = .symlink(target: target)
            }
        }
    }

    @Attribute(.unique) var rawId: String
    var name: String
    var kind: Kind
    var size: UInt64?
    var permissions: UInt32?
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
        kind: Kind = .folder,
        size: UInt64? = nil,
        permissions: UInt32? = nil,
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
        self.permissions = permissions
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
