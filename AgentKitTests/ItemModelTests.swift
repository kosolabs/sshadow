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

    @Test func idReturnsRootContainer() {
        let item = ItemModel(
            id: .rootContainer,
            parentId: .rootContainer,
            name: ""
        )
        #expect(item.id == .rootContainer)
    }

    @Test func idReturnsSSHadowContainer() {
        let item = ItemModel(
            id: .sshadowContainer,
            parentId: .rootContainer,
            name: ".sshadow"
        )
        #expect(item.id == .sshadowContainer)
    }

    @Test func idReturnsTrashContainer() {
        let item = ItemModel(
            id: .trashContainer,
            parentId: .sshadowContainer,
            name: "trash"
        )
        #expect(item.id == .trashContainer)
    }

    @Test func idReturnsWorkingSet() {
        let item = ItemModel(
            id: .workingSet,
            parentId: .rootContainer,
            name: ""
        )
        #expect(item.id == .workingSet)
    }

    @Test func parentIdReturnsRootContainer() {
        let item = ItemModel(parentId: .rootContainer, name: "file.txt")
        #expect(item.parentId == .rootContainer)
    }
}
