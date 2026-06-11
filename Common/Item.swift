import FileProvider
import Foundation

public struct Item: Message, CustomStringConvertible {
    public var description: String {
        let mirror = Mirror(reflecting: self)
        let fields = mirror.children.map { field in
            if field.label == "permissions",
                let value = field.value as? UInt32
            {
                "permissions: 0o\(String(value, radix: 8))"
            } else {
                "\(field.label ?? ""): \(field.value)"
            }
        }.joined(separator: ", ")
        return "Item(\(fields))"
    }

    public enum Kind: Message {
        case file
        case folder
        case symlink(target: String)
    }

    public let rawId: String
    public let rawParentId: String?
    public let name: String
    public let kind: Kind
    public let size: UInt64?
    public let permissions: UInt32?
    public let accessTime: Date?
    public let modifyTime: Date?
    public let createTime: Date?
    public let enumeratedAt: Date?

    public var id: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(rawId)
    }

    public var parentId: NSFileProviderItemIdentifier? {
        if let rawParentId = rawParentId {
            return NSFileProviderItemIdentifier(rawParentId)
        }
        return nil
    }
    
    public var isEnumerated: Bool {
        kind == .folder && enumeratedAt != nil
    }

    public init(
        id: String,
        parentId: String?,
        name: String,
        kind: Kind,
        size: UInt64?,
        permissions: UInt32?,
        accessTime: Date?,
        modifyTime: Date?,
        createTime: Date?,
        enumeratedAt: Date?
    ) {
        self.rawId = id
        self.rawParentId = parentId
        self.name = name
        self.kind = kind
        self.size = size
        self.permissions = permissions
        self.accessTime = accessTime
        self.modifyTime = modifyTime
        self.createTime = createTime
        self.enumeratedAt = enumeratedAt
    }
}
