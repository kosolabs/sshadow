import Foundation

public enum IgnoreFile: Message, PrettyDescribable {
    public struct Version: Message, PrettyDescribable {
        public let modifyTime: Date
        public let size: UInt64

        public init(modifyTime: Date, size: UInt64) {
            self.modifyTime = modifyTime
            self.size = size
        }
    }

    case contents(String, version: Version)
    case unresolved
}

/// The ignore files in each folder from the root down to a parent, root first.
public typealias IgnoreLevels = [[String: IgnoreFile]]
