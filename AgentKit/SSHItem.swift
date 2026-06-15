import Common
import Foundation

struct SSHItem: Message, CustomStringConvertible {
    typealias Stream = AsyncSequence<SSHItem, any Error>
    
    struct EmptyStream: Stream {
        struct AsyncIterator: AsyncIteratorProtocol {
            mutating func next() async throws -> SSHItem? { nil }
        }
        
        func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
    }
    
    var description: String {
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
        return "SSHItem(\(fields))"
    }

    let name: String
    let kind: Item.Kind
    let size: UInt64?
    let flags: Item.Flags?
    let accessTime: Date?
    let modifyTime: Date?
    let createTime: Date?

    init(
        name: String,
        kind: Item.Kind,
        size: UInt64?,
        flags: Item.Flags?,
        accessTime: Date?,
        modifyTime: Date?,
        createTime: Date?
    ) {
        self.name = name
        self.kind = kind
        self.size = size
        self.flags = flags
        self.accessTime = accessTime
        self.modifyTime = modifyTime
        self.createTime = createTime
    }
}
