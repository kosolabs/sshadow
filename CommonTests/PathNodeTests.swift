import FileProvider
import Foundation
import Testing

@testable import Common

struct PathNodeTests {
    @Test func initSetsProperties() {
        let id = NSFileProviderItemIdentifier(UUID().uuidString)
        let parentId = NSFileProviderItemIdentifier(UUID().uuidString)
        let item = PathNode(id: id, parentId: parentId, name: "file.txt")

        #expect(item.id == id)
        #expect(item.parentId == parentId)
        #expect(item.name == "file.txt")
    }

    @Test func idReturnsRootContainer() {
        let item = PathNode(
            id: .rootContainer,
            parentId: .rootContainer,
            name: ""
        )
        #expect(item.id == .rootContainer)
    }

    @Test func idReturnsTrashContainer() {
        let item = PathNode(
            id: .trashContainer,
            parentId: .rootContainer,
            name: ".Trashes"
        )
        #expect(item.id == .trashContainer)
    }

    @Test func idReturnsWorkingSet() {
        let item = PathNode(
            id: .workingSet,
            parentId: .rootContainer,
            name: ""
        )
        #expect(item.id == .workingSet)
    }

    @Test func parentIdReturnsRootContainer() {
        let item = PathNode(parentId: .rootContainer, name: "file.txt")
        #expect(item.parentId == .rootContainer)
    }
}
