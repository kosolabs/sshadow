import Common
import FileProvider
import Foundation
import SwiftData
import Testing

@testable import AgentKit

struct DomainDBTests {
    let db: DomainDB

    init() async throws {
        db = try await DomainDB.open(
            config: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test func initialDbHasRootContainer() async throws {
        let root = try await db.item(for: .rootContainer)

        #expect(root.parent == nil)
        #expect(root.name == "")
    }

    @Test func initialDbHasTrashContainer() async throws {
        let trash = try await db.item(for: .trashContainer)

        #expect(trash.parent == nil)
        #expect(trash.name == ".sshadow/trash")
    }

    @Test func nameReturnsNameForKnownId() async throws {
        let item = try await db.upsert(name: "file.txt", kind: .file)

        let name = try await db.name(of: item.id)

        #expect(name == "file.txt")
    }

    @Test func nameThrowsForUnknownId() async throws {
        let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)

        await #expect(throws: AgentError.itemNotFound(unknownId)) {
            try await db.name(of: unknownId)
        }
    }

    @Test func parentReturnsParentForKnownId() async throws {
        let expected = try await db.upsert(name: "parent", kind: .folder)
        let item = try await db.upsert(
            parentId: expected.id,
            name: "file.txt",
            kind: .file
        )

        let actual = try await db.parent(of: item.id)

        #expect(actual.id == expected.id)
    }

    @Test func parentThrowsForUnknownId() async throws {
        let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)

        await #expect(throws: AgentError.itemNotFound(unknownId)) {
            try await db.parent(of: unknownId)
        }
    }

    @Test func childSucceedsForExistingItem() async throws {
        let expected = try await db.upsert(name: "file.txt", kind: .file)

        let actual = try await db.child(name: "file.txt")

        #expect(actual.id == expected.id)
    }

    @Test func childWithFailThrowsForMissingItem() async throws {
        await #expect(throws: AgentError.itemNotFound) {
            try await db.child(name: "missing.txt")
        }
    }

    @Test func pathBuildsFromNestedItems() async throws {
        let docs = try await db.upsert(name: "docs", kind: .folder)
        let file = try await db.upsert(
            parentId: docs.id,
            name: "notes.txt",
            kind: .file
        )

        let path = try await db.path(for: file.id)

        #expect(path == "docs/notes.txt")
    }

    @Test func pathReturnsNameForDirectChildOfRoot() async throws {
        let file = try await db.upsert(name: "file.txt", kind: .file)

        let path = try await db.path(for: file.id)

        #expect(path == "file.txt")
    }

    @Test func pathReturnsEmptyForRootContainer() async throws {
        let path = try await db.path(for: .rootContainer)

        #expect(path == "")
    }

    @Test func pathReturnsTrashesFolderForTrashContainer() async throws {
        let path = try await db.path(for: .trashContainer)

        #expect(path == ".sshadow/trash")
    }

    @Test func pathSucceedsForFileInTrashContainer() async throws {
        let file = try await db.upsert(
            parentId: .trashContainer,
            name: "file.txt",
            kind: .file
        )

        let path = try await db.path(for: file.id)

        #expect(path == ".sshadow/trash/file.txt")
    }

    @Test func pathThrowsForUnknownId() async throws {
        let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)

        await #expect(throws: AgentError.itemNotFound(unknownId)) {
            try await db.path(for: unknownId)
        }
    }

    @Test func pathForNameInRootContainer() async throws {
        let path = try await db.path(
            for: "file.txt",
            in: .rootContainer
        )

        #expect(path == "file.txt")
    }

    @Test func pathForNameInNestedParent() async throws {
        let docs = try await db.upsert(name: "docs", kind: .folder)
        let notes = try await db.upsert(
            parentId: docs.id,
            name: "notes",
            kind: .folder
        )

        let path = try await db.path(for: "todo.txt", in: notes.id)

        #expect(path == "docs/notes/todo.txt")
    }

    @Test func pathForNameInTrashContainer() async throws {
        let path = try await db.path(
            for: "deleted.txt",
            in: .trashContainer
        )

        #expect(path == ".sshadow/trash/deleted.txt")
    }

    @Test func moveUpdatesParentAndName() async throws {
        let oldParent = try await db.upsert(name: "old", kind: .folder)
        let newParent = try await db.upsert(name: "new", kind: .folder)
        let item = try await db.upsert(
            parentId: oldParent.id,
            name: "old.txt",
            kind: .file
        )

        try await db.move(item.id, toParent: newParent.id, name: "new.txt")

        let actual = try await db.item(for: item.id)
        #expect(actual.parent?.id == newParent.id)
        #expect(actual.name == "new.txt")
    }

    @Test func moveThrowsForUnknownId() async throws {
        let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)

        await #expect(throws: AgentError.itemNotFound(unknownId)) {
            try await db.move(
                unknownId,
                toParent: .rootContainer,
                name: "file.txt"
            )
        }
    }

    @Test func moveUpdatesPath() async throws {
        let src = try await db.upsert(name: "src", kind: .folder)
        let file = try await db.upsert(
            parentId: src.id,
            name: "src",
            kind: .file
        )
        let dest = try await db.upsert(name: "dest", kind: .folder)

        try await db.move(file.id, toParent: dest.id, name: "file.txt")

        let path = try await db.path(for: file.id)
        #expect(path == "dest/file.txt")
    }

    @Test func removeDeletesItem() async throws {
        let item = try await db.upsert(name: "file.txt", kind: .file)

        try await db.remove(item.id)

        #expect(await db.fetch(id: item.id) == nil)
    }

    @Test func removeCascadesToChildren() async throws {
        let folder = try await db.upsert(name: "folder", kind: .folder)
        let child = try await db.upsert(
            parentId: folder.id,
            name: "child.txt",
            kind: .file
        )
        let grandchild = try await db.upsert(
            parentId: child.id,
            name: "deeper.txt",
            kind: .file
        )

        try await db.remove(folder.id)

        #expect(await db.fetch(id: folder.id) == nil)
        #expect(await db.fetch(id: child.id) == nil)
        #expect(await db.fetch(id: grandchild.id) == nil)
    }

    @Test func removeThrowsForUnknownId() async throws {
        let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)

        await #expect(throws: AgentError.itemNotFound(unknownId)) {
            try await db.remove(unknownId)
        }
    }

    @Test func markEnumeratedSetsTimestamp() async throws {
        let folder = try await db.upsert(name: "folder", kind: .folder)

        try await db.markEnumerated(folder.id)

        let row = try await db.item(for: folder.id)
        #expect(row.enumeratedAt != nil)
    }

    @Test func markEnumeratedThrowsForUnknownId() async throws {
        let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)

        await #expect(throws: AgentError.itemNotFound(unknownId)) {
            try await db.markEnumerated(unknownId)
        }
    }

    @Test func upsertAndFetchById() async throws {
        let item = try await db.upsert(name: "hello.txt", kind: .file)

        let actual = try await db.item(for: item.id)
        #expect(actual.id == item.id)
        #expect(actual.parent?.id == .rootContainer)
        #expect(actual.name == "hello.txt")
    }

    @Test func upsertSamePathUpdatesExistingItem() async throws {
        let first = try await db.upsert(
            name: "file.txt",
            kind: .file,
            size: 1
        )
        let second = try await db.upsert(
            name: "file.txt",
            kind: .file,
            size: 2
        )

        #expect(first.id == second.id)
        #expect(second.size == 2)
    }

    @Test func upsertMultipleItems() async throws {
        let parent = try await db.upsert(name: "parent", kind: .folder)

        let first = try await db.upsert(
            parentId: parent.id,
            name: "a.txt",
            kind: .file
        )
        let second = try await db.upsert(
            parentId: parent.id,
            name: "b.txt",
            kind: .file
        )

        let firstRow = try await db.item(for: first.id)
        let secondRow = try await db.item(for: second.id)
        #expect(firstRow.name == "a.txt")
        #expect(secondRow.name == "b.txt")
    }
}
