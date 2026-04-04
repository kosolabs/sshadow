import FileProvider
import Foundation
import SwiftData
import Testing

@testable import Common

struct SSHadowDBTests {
    @Test func upsertAndFetchById() async throws {
        let db = try TestData.getSSHadowDB()

        let id = UUID().uuidString
        let parentId = UUID().uuidString
        let item = SSHItem(id: id, parentId: parentId, name: "hello.txt")

        try await db.upsert(item)
        let fetched = await db.fetch(id: id)

        #expect(fetched != nil)
        #expect(fetched?.id == id)
        #expect(fetched?.parentId == parentId)
        #expect(fetched?.name == "hello.txt")
    }

    @Test func fetchReturnsNilForUnknownId() async throws {
        let db = try TestData.getSSHadowDB()

        let result = await db.fetch(id: UUID().uuidString)
        #expect(result == nil)
    }

    @Test func upsertMultipleItems() async throws {
        let db = try TestData.getSSHadowDB()

        let parentId = UUID().uuidString
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString

        try await db.upsert(
            SSHItem(id: id1, parentId: parentId, name: "a.txt")
        )
        try await db.upsert(
            SSHItem(id: id2, parentId: parentId, name: "b.txt")
        )

        let first = await db.fetch(id: id1)
        let second = await db.fetch(id: id2)

        #expect(first?.name == "a.txt")
        #expect(second?.name == "b.txt")
    }

    @Test func upsertDuplicateIdUpdatesExistingItem() async throws {
        let db = try TestData.getSSHadowDB()

        let id = UUID().uuidString
        let parentId = UUID().uuidString

        try await db.upsert(
            SSHItem(id: id, parentId: parentId, name: "first.txt")
        )
        try await db.upsert(
            SSHItem(id: id, parentId: parentId, name: "second.txt")
        )

        let fetched = await db.fetch(id: id)
        #expect(fetched?.name == "second.txt")
    }
}
