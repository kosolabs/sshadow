import Common
import FileProvider
import Foundation
import Testing

@testable import AgentKit

struct ItemModelTests {
    @Test func initSetsProperties() {
        let id = NSFileProviderItemIdentifier(UUID().uuidString)
        let parentId = NSFileProviderItemIdentifier(UUID().uuidString)
        let item = ItemModel(id: id, parentId: parentId, name: "file.txt")

        #expect(item.id == id)
        #expect(item.parentId == parentId)
        #expect(item.name == "file.txt")
    }

    @Test func defaultKindIsFolder() {
        let item = ItemModel(parentId: .rootContainer, name: "anything")
        #expect(Item.Kind(from: item.kind) == .folder)
    }

    @Test func kindRoundTripsForFile() {
        let item = ItemModel(
            parentId: .rootContainer,
            name: "file.txt",
            kind: .file
        )
        #expect(Item.Kind(from: item.kind) == .file)
    }

    @Test func kindRoundTripsForFolder() {
        let item = ItemModel(
            parentId: .rootContainer,
            name: "folder",
            kind: .folder
        )
        #expect(Item.Kind(from: item.kind) == .folder)
    }

    @Test func kindRoundTripsForSymlinkWithTarget() {
        let item = ItemModel(
            parentId: .rootContainer,
            name: "link",
            kind: .symlink(target: "target.txt")
        )
        #expect(
            Item.Kind(from: item.kind) == .symlink(target: "target.txt")
        )
    }

    @Test func kindRoundTripsForSymlinkWithoutTarget() {
        let item = ItemModel(
            parentId: .rootContainer,
            name: "link",
            kind: .symlink(target: nil)
        )
        #expect(item.kind == .symlink(target: nil))
    }

    @Test func kindCanBeReassigned() {
        let item = ItemModel(parentId: .rootContainer, name: "x")
        item.kind = .file
        #expect(Item.Kind(from: item.kind) == .file)
        item.kind = .symlink(target: "elsewhere")
        #expect(
            Item.Kind(from: item.kind) == .symlink(target: "elsewhere")
        )
        item.kind = .folder
        #expect(Item.Kind(from: item.kind) == .folder)
    }

    @Test func initFromItemCopiesEveryField() {
        let id = UUID().uuidString
        let parentId = UUID().uuidString
        let modify = Date(timeIntervalSince1970: 555)
        let source = Item(
            id: id,
            parentId: parentId,
            name: "from-item.txt",
            kind: .symlink(target: "dest"),
            size: 17,
            permissions: 0o755,
            accessTime: nil,
            modifyTime: modify,
            createTime: nil
        )

        let model = ItemModel(from: source)

        #expect(model.id.rawValue == id)
        #expect(model.parentId.rawValue == parentId)
        #expect(model.name == "from-item.txt")
        #expect(model.kind == .symlink(target: "dest"))
        #expect(model.size == 17)
        #expect(model.permissions == 0o755)
        #expect(model.accessTime == nil)
        #expect(model.modifyTime == modify)
        #expect(model.createTime == nil)
    }

    @Test func itemInitFromModelReturnsEquivalent() {
        let modify = Date(timeIntervalSince1970: 999)
        let model = ItemModel(
            id: NSFileProviderItemIdentifier("abc"),
            parentId: NSFileProviderItemIdentifier("def"),
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
        #expect(result.rawParentId == "def")
        #expect(result.name == "round.txt")
        #expect(result.kind == .file)
        #expect(result.size == 8)
        #expect(result.permissions == 0o600)
        #expect(result.accessTime == nil)
        #expect(result.modifyTime == modify)
        #expect(result.createTime == nil)
    }
}
