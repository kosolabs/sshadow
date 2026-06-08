import Common
import FileProvider
import Foundation
import Testing

@testable import AgentKit

struct ItemModelTests {
    @Test func initSetsProperties() {
        let id = NSFileProviderItemIdentifier(UUID().uuidString)
        let parent = ItemModel(name: "parent")
        let item = ItemModel(id: id, parent: parent, name: "file.txt")

        #expect(item.id == id)
        #expect(item.parent == parent)
        #expect(item.name == "file.txt")
    }

    @Test func defaultKindIsFolder() {
        let item = ItemModel(name: "anything")
        #expect(item.kind == .folder)
    }

    @Test func kindRoundTripsForFile() {
        let item = ItemModel(name: "file.txt", kind: .file)
        #expect(Item.Kind(from: item.kind) == .file)
    }

    @Test func kindRoundTripsForFolder() {
        let item = ItemModel(name: "folder", kind: .folder)
        #expect(Item.Kind(from: item.kind) == .folder)
    }

    @Test func kindRoundTripsForSymlink() {
        let item = ItemModel(name: "link", kind: .symlink(target: "target.txt"))
        #expect(Item.Kind(from: item.kind) == .symlink(target: "target.txt"))
    }

    @Test func itemInitFromModelReturnsEquivalent() {
        let modify = Date(timeIntervalSince1970: 999)
        let model = ItemModel(
            id: NSFileProviderItemIdentifier("abc"),
            name: "round.txt",
            kind: .file,
            size: 8,
            permissions: 0o600,
            accessTime: nil,
            modifyTime: modify,
            createTime: nil
        )

        let result = Item(from: model)

        #expect(result.rawId == "abc")
        #expect(result.parentId == nil)
        #expect(result.name == "round.txt")
        #expect(result.kind == .file)
        #expect(result.size == 8)
        #expect(result.permissions == 0o600)
        #expect(result.accessTime == nil)
        #expect(result.modifyTime == modify)
        #expect(result.createTime == nil)
    }
}
