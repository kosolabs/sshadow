import Common
import Foundation

struct SSHItem: Message, PrettyDescribable {
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
