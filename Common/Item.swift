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

    public struct Flags: OptionSet, Message, CustomStringConvertible {
        public var description: String {
            var flags = [String]()
            flags.append("rawValue: \(rawValue)")
            if contains(.executable) {
                flags.append("executable")
            }
            if contains(.readable) {
                flags.append("readable")
            }
            if contains(.writable) {
                flags.append("writable")
            }
            return "Flags(\(flags.joined(separator: ", ")))"
        }

        public let rawValue: UInt8

        public static let executable = Flags(rawValue: 1 << 0)
        public static let readable = Flags(rawValue: 1 << 1)
        public static let writable = Flags(rawValue: 1 << 2)
        
        public static let all: Flags = [.executable, .readable, .writable]
        public static let rw: Flags = [.readable, .writable]

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        
        public static func from(_ value: NSFileProviderFileSystemFlags?) -> Flags? {
            guard let fpFlags = value else {
                return nil
            }
            return Flags(from: fpFlags)
        }
        
        public init(from fpFlags: NSFileProviderFileSystemFlags) {
            self = []
            if fpFlags.contains(.userExecutable) {
                self.insert(.executable)
            }
            if fpFlags.contains(.userReadable) {
                self.insert(.readable)
            }
            if fpFlags.contains(.userWritable) {
                self.insert(.writable)
            }
        }

        public static func from<T: BinaryInteger>(_ value: T?) -> Flags? {
            guard let mode = value else {
                return nil
            }
            return Flags(from: mode_t(mode))
        }
        
        public init(from mode: mode_t) {
            self = []
            if mode & S_IRUSR != 0 {
                self.insert(.readable)
            }
            if mode & S_IWUSR != 0 {
                self.insert(.writable)
            }
            if mode & S_IXUSR != 0 {
                self.insert(.executable)
            }
        }

        public var mode: mode_t {
            var mode: mode_t = 0
            if contains(.readable) {
                mode |= S_IRUSR
            }
            if contains(.writable) {
                mode |= S_IWUSR
            }
            if contains(.executable) {
                mode |= S_IXUSR
            }
            return mode
        }
    }

    public let rawId: String
    public let rawParentId: String?
    public let name: String
    public let kind: Kind
    public let size: UInt64?
    public let flags: Flags?
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
        flags: Flags?,
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
        self.flags = flags
        self.accessTime = accessTime
        self.modifyTime = modifyTime
        self.createTime = createTime
        self.enumeratedAt = enumeratedAt
    }
}
