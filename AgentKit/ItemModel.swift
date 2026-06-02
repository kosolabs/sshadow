import Common
import FileProvider
import Foundation
import SwiftData

extension Item {
    init(from item: ItemModel) {
        self.init(
            id: item.rawId,
            parentId: item.rawParentId,
            name: item.name,
            kind: Item.Kind(from: item.kind),
            size: item.size,
            permissions: item.permissions,
            accessTime: item.accessTime,
            modifyTime: item.modifyTime,
            createTime: item.createTime
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
    var rawParentId: String
    var name: String
    var kind: Kind
    var size: UInt64?
    var permissions: UInt32?
    var accessTime: Date?
    var modifyTime: Date?
    var createTime: Date?
    var enumeratedAt: Date?

    init(
        id: NSFileProviderItemIdentifier =
            NSFileProviderItemIdentifier(UUID().uuidString),
        parentId: NSFileProviderItemIdentifier,
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
        self.rawParentId = parentId.rawValue
        self.name = name
        self.kind = kind
        self.size = size
        self.permissions = permissions
        self.accessTime = accessTime
        self.modifyTime = modifyTime
        self.createTime = createTime
        self.enumeratedAt = enumeratedAt
    }

    convenience init(from item: Item) {
        self.init(
            id: item.id,
            parentId: item.parentId,
            name: item.name,
            kind: Kind(from: item.kind),
            size: item.size,
            permissions: item.permissions,
            accessTime: item.accessTime,
            modifyTime: item.modifyTime,
            createTime: item.createTime
        )
    }

    var id: NSFileProviderItemIdentifier {
        get { NSFileProviderItemIdentifier(rawId) }
        set { rawId = newValue.rawValue }
    }

    var parentId: NSFileProviderItemIdentifier {
        get { NSFileProviderItemIdentifier(rawParentId) }
        set { rawParentId = newValue.rawValue }
    }
}
