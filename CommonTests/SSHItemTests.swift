import Foundation
import Testing

@testable import Common

struct SSHItemTests {
    @Test func initSetsProperties() {
        let id = UUID().uuidString
        let parentId = UUID().uuidString
        let item = SSHItem(id: id, parentId: parentId, name: "file.txt")

        #expect(item.id == id)
        #expect(item.parentId == parentId)
        #expect(item.name == "file.txt")
    }
}
