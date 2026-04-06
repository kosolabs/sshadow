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
        let actual = try #require(await db.fetch(id: id))

        #expect(actual.id == id)
        #expect(actual.parentId == parentId)
        #expect(actual.name == "hello.txt")
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

        let first = try #require(await db.fetch(id: id1))
        let second = try #require(await db.fetch(id: id2))

        #expect(first.name == "a.txt")
        #expect(second.name == "b.txt")
    }

    @Test func fetchByParentIdAndName() async throws {
        let db = try TestData.getSSHadowDB()

        let parentId = UUID().uuidString
        let id = UUID().uuidString

        try await db.upsert(
            SSHItem(id: id, parentId: parentId, name: "hello.txt")
        )

        let actual = try #require(
            await db.fetch(parentId: parentId, name: "hello.txt")
        )

        #expect(actual.id == id)
        #expect(actual.parentId == parentId)
        #expect(actual.name == "hello.txt")
    }

    @Test func fetchByParentIdAndNameReturnsNilWhenNotFound() async throws {
        let db = try TestData.getSSHadowDB()

        let parentId = UUID().uuidString

        try await db.upsert(
            SSHItem(
                id: UUID().uuidString,
                parentId: parentId,
                name: "exists.txt"
            )
        )

        let wrongName = await db.fetch(
            parentId: parentId,
            name: "missing.txt"
        )
        let wrongParent = await db.fetch(
            parentId: UUID().uuidString,
            name: "exists.txt"
        )

        #expect(wrongName == nil)
        #expect(wrongParent == nil)
    }

    @Test func fetchByParentIdAndNameDistinguishesSiblings() async throws {
        let db = try TestData.getSSHadowDB()

        let parentId = UUID().uuidString

        try await db.upsert(
            SSHItem(
                id: UUID().uuidString,
                parentId: parentId,
                name: "a.txt"
            )
        )
        try await db.upsert(
            SSHItem(
                id: UUID().uuidString,
                parentId: parentId,
                name: "b.txt"
            )
        )

        let actual = try #require(
            await db.fetch(parentId: parentId, name: "b.txt")
        )

        #expect(actual.name == "b.txt")
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

        let actual = try #require(await db.fetch(id: id))
        #expect(actual.name == "second.txt")
    }
}
