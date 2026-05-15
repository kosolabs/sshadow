import Foundation

public struct FileInfo: Message, CustomStringConvertible {
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
        return "FileInfo(\(fields))"
    }

    public enum FileType: Message {
        case file
        case folder
        case symlink(target: String)
    }

    public let id: String
    public let parentId: String
    public let name: String
    public let type: FileType
    public let size: UInt64
    public let permissions: UInt32
    public let accessTime: Date?
    public let modifyTime: Date?
    public let createTime: Date?

    public init(
        id: String,
        parentId: String,
        name: String,
        type: FileType,
        size: UInt64,
        permissions: UInt32,
        accessTime: Date?,
        modifyTime: Date?,
        createTime: Date?
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.type = type
        self.size = size
        self.permissions = permissions
        self.accessTime = accessTime
        self.modifyTime = modifyTime
        self.createTime = createTime
    }
}
