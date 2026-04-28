import Foundation

public struct FileInfo: Codable, Sendable {
    public let id: String
    public let parentId: String
    public let name: String
    public let isDirectory: Bool
    public let size: UInt64
    public let permissions: UInt32
    public let accessTime: Date?
    public let modifyTime: Date?
    public let createTime: Date?

    public init(
        id: String,
        parentId: String,
        name: String,
        isDirectory: Bool,
        size: UInt64,
        permissions: UInt32,
        accessTime: Date?,
        modifyTime: Date?,
        createTime: Date?
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.permissions = permissions
        self.accessTime = accessTime
        self.modifyTime = modifyTime
        self.createTime = createTime
    }
}
