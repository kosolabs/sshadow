import Foundation

public typealias IgnoreSnapshot = [IgnoreFolder]

public struct IgnoreFolder: Message, PrettyDescribable {
    public let path: String
    public let files: [IgnoreFile]

    public init(path: String, files: [IgnoreFile]) {
        self.path = path
        self.files = files
    }
}

public struct IgnoreFile: Message, PrettyDescribable {
    public enum Content: Message, PrettyDescribable {
        case loaded(String, version: Version)
        case unresolved
    }

    public struct Version: Message, PrettyDescribable {
        public let modifyTime: Date
        public let size: UInt64

        public init(modifyTime: Date, size: UInt64) {
            self.modifyTime = modifyTime
            self.size = size
        }
    }

    public let name: String
    public let content: Content

    public init(name: String, content: Content) {
        self.name = name
        self.content = content
    }
}
