import Common
import FileProvider
import Foundation
import SwiftData
import Testing

@testable import AgentKit

private func openInMemoryDb() async throws -> DomainDB {
    try await DomainDB.open(
        config: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

struct DomainDBTests {
    struct FetchTests {
        @Test func fetchReturnsNilForUnknownId() async throws {
            let db = try await openInMemoryDb()

            let result = await db.fetch(
                id: NSFileProviderItemIdentifier(UUID().uuidString)
            )
            #expect(result == nil)
        }

        @Test func fetchByParentIdAndName() async throws {
            let db = try await openInMemoryDb()

            let parentId = NSFileProviderItemIdentifier(UUID().uuidString)
            let id = NSFileProviderItemIdentifier(UUID().uuidString)

            try await db.upsert(
                ItemModel(id: id, parentId: parentId, name: "hello.txt")
            )

            let actual = try #require(
                await db.fetch(parentId: parentId, name: "hello.txt")
            )

            #expect(actual.id == id)
            #expect(actual.parentId == parentId)
            #expect(actual.name == "hello.txt")
        }

        @Test func fetchByParentIdAndNameReturnsNilWhenNotFound() async throws {
            let db = try await openInMemoryDb()

            let parentId = NSFileProviderItemIdentifier(UUID().uuidString)

            try await db.upsert(
                ItemModel(parentId: parentId, name: "exists.txt")
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
            let db = try await openInMemoryDb()

            let parentId = NSFileProviderItemIdentifier(UUID().uuidString)

            try await db.upsert(
                ItemModel(parentId: parentId, name: "a.txt")
            )
            try await db.upsert(
                ItemModel(parentId: parentId, name: "b.txt")
            )

            let actual = try #require(
                await db.fetch(parentId: parentId, name: "b.txt")
            )

            #expect(actual.name == "b.txt")
        }
    }

    struct InitTests {
        @Test func initialDbHasRootContainer() async throws {
            let db = try await openInMemoryDb()

            let root = try #require(await db.fetch(id: .rootContainer))

            #expect(root.parentId == .rootContainer)
            #expect(root.name == "")
        }

        @Test func initialDbHasSSHadowFolder() async throws {
            let db = try await openInMemoryDb()

            let folder = try #require(await db.fetch(id: .sshadowContainer))

            #expect(folder.parentId == .rootContainer)
            #expect(folder.name == ".sshadow")
        }

        @Test func initialDbHasTrashContainer() async throws {
            let db = try await openInMemoryDb()

            let trash = try #require(await db.fetch(id: .trashContainer))

            #expect(trash.parentId == .sshadowContainer)
            #expect(trash.name == "trash")
        }

        @Test func initialDbHasWorkingSet() async throws {
            let db = try await openInMemoryDb()

            let workingSet = try #require(await db.fetch(id: .workingSet))

            #expect(workingSet.parentId == .rootContainer)
            #expect(workingSet.name == "")
        }

        @Test func virtualContainersCarryFolderSentinel() async throws {
            let db = try await openInMemoryDb()

            for id in [
                NSFileProviderItemIdentifier.rootContainer,
                .sshadowContainer,
                .trashContainer,
                .workingSet,
            ] {
                let container = try #require(await db.fetch(id: id))
                #expect(container.kind == .folder)
                #expect(container.size == nil)
                #expect(container.permissions == nil)
                #expect(container.accessTime == nil)
                #expect(container.modifyTime == nil)
                #expect(container.createTime == nil)
            }
        }
    }

    struct NameTests {
        @Test func nameReturnsNameForKnownId() async throws {
            let db = try await openInMemoryDb()

            let id = NSFileProviderItemIdentifier(UUID().uuidString)
            try await db.upsert(
                ItemModel(id: id, parentId: .rootContainer, name: "file.txt")
            )

            let name = try await db.name(of: id)
            #expect(name == "file.txt")
        }

        @Test func nameThrowsForUnknownId() async throws {
            let db = try await openInMemoryDb()

            let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)

            await #expect(throws: NSFileProviderError.self) {
                try await db.name(of: unknownId)
            }
        }
    }

    struct ParentTests {
        @Test func parentReturnsParentForKnownId() async throws {
            let db = try await openInMemoryDb()

            let parentId = NSFileProviderItemIdentifier(UUID().uuidString)
            let id = NSFileProviderItemIdentifier(UUID().uuidString)
            try await db.upsert(
                ItemModel(id: id, parentId: parentId, name: "file.txt")
            )

            let actual = try await db.parent(of: id)
            #expect(actual == parentId)
        }

        @Test func parentThrowsForUnknownId() async throws {
            let db = try await openInMemoryDb()

            let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)

            await #expect(throws: AgentError.itemNotFound(unknownId.rawValue)) {
                try await db.parent(of: unknownId)
            }
        }
    }

    struct ChildTests {
        @Test func childCreatesItemByDefault() async throws {
            let db = try await openInMemoryDb()

            let id = try await db.child(path: "new-file.txt")

            let item = try #require(await db.fetch(id: id))
            #expect(item.name == "new-file.txt")
            #expect(item.parentId == .rootContainer)
        }

        @Test func childReturnsExistingItem() async throws {
            let db = try await openInMemoryDb()

            let first = try await db.child(path: "same.txt")
            let second = try await db.child(path: "same.txt")

            #expect(first == second)
        }

        @Test func childWithFailThrowsForMissingItem() async throws {
            let db = try await openInMemoryDb()

            let itemId = NSFileProviderItemIdentifier.rootContainer

            await #expect(throws: AgentError.itemNotFound(itemId.rawValue)) {
                try await db.child(
                    path: "nonexistent.txt",
                    ifNotExists: .fail
                )
            }
        }

        @Test func childWithFailSucceedsForExistingItem() async throws {
            let db = try await openInMemoryDb()

            let created = try await db.child(path: "exists.txt")
            let found = try await db.child(
                path: "exists.txt",
                ifNotExists: .fail
            )

            #expect(created == found)
        }
    }

    struct PathTests {
        @Test func pathBuildsFromNestedItems() async throws {
            let db = try await openInMemoryDb()

            let fileId = try await db.child(path: "Documents/notes.txt")

            let path = await db.path(for: fileId)
            #expect(path == "Documents/notes.txt")
        }

        @Test func pathReturnsNameForDirectChildOfRoot() async throws {
            let db = try await openInMemoryDb()

            let id = try await db.child(path: "file.txt")

            let path = await db.path(for: id)
            #expect(path == "file.txt")
        }

        @Test func pathReturnsEmptyForRootContainer() async throws {
            let db = try await openInMemoryDb()

            let path = await db.path(for: .rootContainer)
            #expect(path == "")
        }

        @Test func pathReturnsTrashesFolderForTrashContainer() async throws {
            let db = try await openInMemoryDb()

            let path = await db.path(for: .trashContainer)
            #expect(path == ".sshadow/trash")
        }

        @Test func pathSucceedsForFileInTrashContainer() async throws {
            let db = try await openInMemoryDb()

            let fileId = try await db.child(of: .trashContainer, path: "file")
            let path = await db.path(for: fileId)
            #expect(path == ".sshadow/trash/file")
        }

        @Test func pathReturnsEmptyForUnknownId() async throws {
            let db = try await openInMemoryDb()

            let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)
            let path = await db.path(for: unknownId)
            #expect(path == "")
        }

        @Test func pathForNameInRootContainer() async throws {
            let db = try await openInMemoryDb()

            let path = await db.path(
                for: "file.txt",
                in: .rootContainer
            )
            #expect(path == "file.txt")
        }

        @Test func pathForNameInNestedParent() async throws {
            let db = try await openInMemoryDb()

            let parentId = try await db.child(path: "Documents/Notes")

            let path = await db.path(for: "todo.txt", in: parentId)
            #expect(path == "Documents/Notes/todo.txt")
        }

        @Test func pathForNameInTrashContainer() async throws {
            let db = try await openInMemoryDb()

            let path = await db.path(
                for: "deleted.txt",
                in: .trashContainer
            )
            #expect(path == ".sshadow/trash/deleted.txt")
        }
    }

    struct MoveTests {
        @Test func moveUpdatesParentAndName() async throws {
            let db = try await openInMemoryDb()

            let oldParent = NSFileProviderItemIdentifier(UUID().uuidString)
            let newParent = NSFileProviderItemIdentifier(UUID().uuidString)
            let id = NSFileProviderItemIdentifier(UUID().uuidString)

            try await db.upsert(
                ItemModel(id: id, parentId: oldParent, name: "old.txt")
            )
            try await db.move(id, toParent: newParent, name: "new.txt")

            let actual = try #require(await db.fetch(id: id))
            #expect(actual.parentId == newParent)
            #expect(actual.name == "new.txt")
        }

        @Test func moveThrowsForUnknownId() async throws {
            let db = try await openInMemoryDb()

            let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)
            let newParent = NSFileProviderItemIdentifier(UUID().uuidString)

            await #expect(throws: NSFileProviderError.self) {
                try await db.move(
                    unknownId,
                    toParent: newParent,
                    name: "file.txt"
                )
            }
        }

        @Test func moveUpdatesPath() async throws {
            let db = try await openInMemoryDb()

            let fileId = try await db.child(path: "src/file.txt")
            let destId = try await db.child(path: "dst")

            try await db.move(fileId, toParent: destId, name: "file.txt")

            let path = await db.path(for: fileId)
            #expect(path == "dst/file.txt")
        }
    }

    struct UpsertTests {
        @Test func upsertAndFetchById() async throws {
            let db = try await openInMemoryDb()

            let id = NSFileProviderItemIdentifier(UUID().uuidString)
            let parentId = NSFileProviderItemIdentifier(UUID().uuidString)
            let item = ItemModel(id: id, parentId: parentId, name: "hello.txt")

            try await db.upsert(item)
            let actual = try #require(await db.fetch(id: id))

            #expect(actual.id == id)
            #expect(actual.parentId == parentId)
            #expect(actual.name == "hello.txt")
        }

        @Test func upsertDuplicateIdUpdatesExistingItem() async throws {
            let db = try await openInMemoryDb()

            let id = NSFileProviderItemIdentifier(UUID().uuidString)
            let parentId = NSFileProviderItemIdentifier(UUID().uuidString)

            try await db.upsert(
                ItemModel(id: id, parentId: parentId, name: "first.txt")
            )
            try await db.upsert(
                ItemModel(id: id, parentId: parentId, name: "second.txt")
            )

            let actual = try #require(await db.fetch(id: id))
            #expect(actual.name == "second.txt")
        }

        @Test func upsertMultipleItems() async throws {
            let db = try await openInMemoryDb()

            let parentId = NSFileProviderItemIdentifier(UUID().uuidString)
            let id1 = NSFileProviderItemIdentifier(UUID().uuidString)
            let id2 = NSFileProviderItemIdentifier(UUID().uuidString)

            try await db.upsert(
                ItemModel(id: id1, parentId: parentId, name: "a.txt")
            )
            try await db.upsert(
                ItemModel(id: id2, parentId: parentId, name: "b.txt")
            )

            let first = try #require(await db.fetch(id: id1))
            let second = try #require(await db.fetch(id: id2))

            #expect(first.name == "a.txt")
            #expect(second.name == "b.txt")
        }
    }
}
