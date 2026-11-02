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
}
