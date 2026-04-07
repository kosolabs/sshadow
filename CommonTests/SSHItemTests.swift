import FileProvider
import Foundation
import Testing

@testable import Common

struct SSHItemTests {
    @Test func initSetsProperties() {
        let id = NSFileProviderItemIdentifier(UUID().uuidString)
        let parentId = NSFileProviderItemIdentifier(UUID().uuidString)
        let item = SSHItem(id: id, parentId: parentId, name: "file.txt")

        #expect(item.id == id)
        #expect(item.parentId == parentId)
        #expect(item.name == "file.txt")
    }

    @Test func idReturnsRootContainer() {
        let item = SSHItem(
            id: .rootContainer,
            parentId: .rootContainer,
            name: ""
        )
        #expect(item.id == .rootContainer)
    }

    @Test func idReturnsTrashContainer() {
        let item = SSHItem(
            id: .trashContainer,
            parentId: .rootContainer,
            name: ".Trashes"
        )
        #expect(item.id == .trashContainer)
    }

    @Test func idReturnsWorkingSet() {
        let item = SSHItem(
            id: .workingSet,
            parentId: .rootContainer,
            name: ""
        )
        #expect(item.id == .workingSet)
    }

    @Test func idReturnsCustomId() {
        let id = NSFileProviderItemIdentifier(UUID().uuidString)
        let item = SSHItem(id: id, parentId: .rootContainer, name: "file.txt")
        #expect(item.id == id)
    }

    @Test func parentIdReturnsRootContainer() {
        let item = SSHItem(parentId: .rootContainer, name: "file.txt")
        #expect(item.parentId == .rootContainer)
    }

    @Test func parentIdReturnsCustomId() {
        let parentId = NSFileProviderItemIdentifier(UUID().uuidString)
        let item = SSHItem(parentId: parentId, name: "file.txt")
        #expect(item.parentId == parentId)
    }
}
