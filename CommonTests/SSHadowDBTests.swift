import FileProvider
import Foundation
import SwiftData
import Testing

@testable import Common

struct SSHadowDBTests {
    @Test func upsertAndFetchById() async throws {
        let db = try TestData.getSSHadowDB()

        let id = NSFileProviderItemIdentifier(UUID().uuidString)
        let parentId = NSFileProviderItemIdentifier(UUID().uuidString)
        let item = SSHItem(id: id, parentId: parentId, name: "hello.txt")

        try await db.upsert(item)
        let actual = try #require(await db.fetch(id: id))

        #expect(actual.id == id)
        #expect(actual.parentId == parentId)
        #expect(actual.name == "hello.txt")
    }

    @Test func fetchReturnsNilForUnknownId() async throws {
        let db = try TestData.getSSHadowDB()

        let result = await db.fetch(
            id: NSFileProviderItemIdentifier(UUID().uuidString)
        )
        #expect(result == nil)
    }

    @Test func upsertMultipleItems() async throws {
        let db = try TestData.getSSHadowDB()

        let parentId = NSFileProviderItemIdentifier(UUID().uuidString)
        let id1 = NSFileProviderItemIdentifier(UUID().uuidString)
        let id2 = NSFileProviderItemIdentifier(UUID().uuidString)

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

        let parentId = NSFileProviderItemIdentifier(UUID().uuidString)
        let id = NSFileProviderItemIdentifier(UUID().uuidString)

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

        let parentId = NSFileProviderItemIdentifier(UUID().uuidString)

        try await db.upsert(
            SSHItem(parentId: parentId, name: "exists.txt")
        )

        let wrongName = await db.fetch(
            parentId: parentId,
            name: "missing.txt"
        )
        let wrongParent = await db.fetch(
            parentId: NSFileProviderItemIdentifier(UUID().uuidString),
            name: "exists.txt"
        )

        #expect(wrongName == nil)
        #expect(wrongParent == nil)
    }

    @Test func fetchByParentIdAndNameDistinguishesSiblings() async throws {
        let db = try TestData.getSSHadowDB()

        let parentId = NSFileProviderItemIdentifier(UUID().uuidString)

        try await db.upsert(
            SSHItem(parentId: parentId, name: "a.txt")
        )
        try await db.upsert(
            SSHItem(parentId: parentId, name: "b.txt")
        )

        let actual = try #require(
            await db.fetch(parentId: parentId, name: "b.txt")
        )

        #expect(actual.name == "b.txt")
    }

    @Test func seedInsertsRootContainer() async throws {
        let db = try TestData.getSSHadowDB()
        try await db.seed()

        let root = try #require(await db.fetch(id: .rootContainer))

        #expect(root.parentId == .rootContainer)
        #expect(root.name == "")
    }

    @Test func seedInsertsTrashContainer() async throws {
        let db = try TestData.getSSHadowDB()
        try await db.seed()

        let trash = try #require(await db.fetch(id: .trashContainer))

        #expect(trash.parentId == .rootContainer)
        #expect(trash.name == ".Trashes")
    }

    @Test func seedInsertsWorkingSet() async throws {
        let db = try TestData.getSSHadowDB()
        try await db.seed()

        let workingSet = try #require(await db.fetch(id: .workingSet))

        #expect(workingSet.parentId == .rootContainer)
        #expect(workingSet.name == "")
    }

    @Test func seedIsIdempotent() async throws {
        let db = try TestData.getSSHadowDB()
        try await db.seed()
        try await db.seed()

        let root = try #require(await db.fetch(id: .rootContainer))
        #expect(root.parentId == .rootContainer)
    }

    @Test func pathBuildsFromNestedItems() async throws {
        let db = try TestData.getSSHadowDB()
        try await db.seed()

        let dirId = try await db.child(of: .rootContainer, name: "Documents")
        let fileId = try await db.child(of: dirId, name: "notes.txt")

        let path = try await db.path(for: fileId)
        #expect(path == "Documents/notes.txt")
    }

    @Test func pathReturnsNameForDirectChildOfRoot() async throws {
        let db = try TestData.getSSHadowDB()
        try await db.seed()

        let id = try await db.child(of: .rootContainer, name: "file.txt")

        let path = try await db.path(for: id)
        #expect(path == "file.txt")
    }

    @Test func pathReturnsEmptyForRootContainer() async throws {
        let db = try TestData.getSSHadowDB()
        try await db.seed()

        let path = try await db.path(for: .rootContainer)
        #expect(path == "")
    }

    @Test func upsertDuplicateIdUpdatesExistingItem() async throws {
        let db = try TestData.getSSHadowDB()

        let id = NSFileProviderItemIdentifier(UUID().uuidString)
        let parentId = NSFileProviderItemIdentifier(UUID().uuidString)

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
