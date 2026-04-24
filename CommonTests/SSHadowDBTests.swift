import FileProvider
import Foundation
import SwiftData
import Testing

@testable import Common

struct SSHadowDBTests {
    struct FetchTests {
        @Test func fetchReturnsNilForUnknownId() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let result = await db.fetch(
                id: NSFileProviderItemIdentifier(UUID().uuidString)
            )
            #expect(result == nil)
        }
        
        @Test func fetchByParentIdAndName() async throws {
            let db = try await TestData.getSSHadowDb()
            
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
            let db = try await TestData.getSSHadowDb()
            
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
            let db = try await TestData.getSSHadowDb()
            
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
    }
    
    struct InitTests {
        @Test func initialDbHasRootContainer() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let root = try #require(await db.fetch(id: .rootContainer))
            
            #expect(root.parentId == .rootContainer)
            #expect(root.name == "")
        }
        
        @Test func initialDbHasTrashContainer() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let trash = try #require(await db.fetch(id: .trashContainer))
            
            #expect(trash.parentId == .rootContainer)
            #expect(trash.name == ".Trashes")
        }
        
        @Test func initialDbHasWorkingSet() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let workingSet = try #require(await db.fetch(id: .workingSet))
            
            #expect(workingSet.parentId == .rootContainer)
            #expect(workingSet.name == "")
        }
    }
    
    struct NameTests {
        @Test func nameReturnsNameForKnownId() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let id = NSFileProviderItemIdentifier(UUID().uuidString)
            try await db.upsert(
                SSHItem(id: id, parentId: .rootContainer, name: "file.txt")
            )
            
            let name = try await db.name(of: id)
            #expect(name == "file.txt")
        }
        
        @Test func nameThrowsForUnknownId() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)
            
            await #expect(throws: NSFileProviderError.self) {
                try await db.name(of: unknownId)
            }
        }
    }
    
    struct ParentTests {
        @Test func parentReturnsParentForKnownId() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let parentId = NSFileProviderItemIdentifier(UUID().uuidString)
            let id = NSFileProviderItemIdentifier(UUID().uuidString)
            try await db.upsert(
                SSHItem(id: id, parentId: parentId, name: "file.txt")
            )
            
            let actual = try await db.parent(of: id)
            #expect(actual == parentId)
        }
        
        @Test func parentThrowsForUnknownId() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)
            
            await #expect(throws: NSFileProviderError.self) {
                try await db.parent(of: unknownId)
            }
        }
    }
    
    struct ChildTests {
        @Test func childCreatesItemByDefault() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let id = try await db.child(path: "new-file.txt")
            
            let item = try #require(await db.fetch(id: id))
            #expect(item.name == "new-file.txt")
            #expect(item.parentId == .rootContainer)
        }
        
        @Test func childReturnsExistingItem() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let first = try await db.child(path: "same.txt")
            let second = try await db.child(path: "same.txt")
            
            #expect(first == second)
        }
        
        @Test func childWithFailThrowsForMissingItem() async throws {
            let db = try await TestData.getSSHadowDb()
            
            await #expect(throws: NSFileProviderError.self) {
                try await db.child(
                    path: "nonexistent.txt",
                    ifNotExists: .fail
                )
            }
        }
        
        @Test func childWithFailSucceedsForExistingItem() async throws {
            let db = try await TestData.getSSHadowDb()
            
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
            let db = try await TestData.getSSHadowDb()
            
            let fileId = try await db.child(path: "Documents/notes.txt")
            
            let path = await db.path(for: fileId)
            #expect(path == "Documents/notes.txt")
        }
        
        @Test func pathReturnsNameForDirectChildOfRoot() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let id = try await db.child(path: "file.txt")
            
            let path = await db.path(for: id)
            #expect(path == "file.txt")
        }
        
        @Test func pathReturnsEmptyForRootContainer() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let path = await db.path(for: .rootContainer)
            #expect(path == "")
        }
        
        @Test func pathReturnsTrashesFolderForTrashContainer() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let path = await db.path(for: .trashContainer)
            #expect(path == ".Trashes")
        }
        
        @Test func pathSucceedsForFileInTrashContainer() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let fileId = try await db.child(of: .trashContainer, path: "file")
            let path = await db.path(for: fileId)
            #expect(path == ".Trashes/file")
        }
        
        @Test func pathReturnsEmptyForUnknownId() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)
            let path = await db.path(for: unknownId)
            #expect(path == "")
        }
        
        @Test func pathForNameInRootContainer() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let path = await db.path(
                for: "file.txt", in: .rootContainer
            )
            #expect(path == "file.txt")
        }
        
        @Test func pathForNameInNestedParent() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let parentId = try await db.child(path: "Documents/Notes")
            
            let path = await db.path(for: "todo.txt", in: parentId)
            #expect(path == "Documents/Notes/todo.txt")
        }
        
        @Test func pathForNameInTrashContainer() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let path = await db.path(
                for: "deleted.txt", in: .trashContainer
            )
            #expect(path == ".Trashes/deleted.txt")
        }
    }
    
    struct MoveTests {
        @Test func moveUpdatesParentAndName() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let oldParent = NSFileProviderItemIdentifier(UUID().uuidString)
            let newParent = NSFileProviderItemIdentifier(UUID().uuidString)
            let id = NSFileProviderItemIdentifier(UUID().uuidString)
            
            try await db.upsert(
                SSHItem(id: id, parentId: oldParent, name: "old.txt")
            )
            try await db.move(id, toParent: newParent, name: "new.txt")
            
            let actual = try #require(await db.fetch(id: id))
            #expect(actual.parentId == newParent)
            #expect(actual.name == "new.txt")
        }
        
        @Test func moveThrowsForUnknownId() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let unknownId = NSFileProviderItemIdentifier(UUID().uuidString)
            let newParent = NSFileProviderItemIdentifier(UUID().uuidString)
            
            await #expect(throws: NSFileProviderError.self) {
                try await db.move(
                    unknownId, toParent: newParent, name: "file.txt"
                )
            }
        }
        
        @Test func moveUpdatesPath() async throws {
            let db = try await TestData.getSSHadowDb()
            
            let fileId = try await db.child(path: "src/file.txt")
            let destId = try await db.child(path: "dst")
            
            try await db.move(fileId, toParent: destId, name: "file.txt")
            
            let path = await db.path(for: fileId)
            #expect(path == "dst/file.txt")
        }
    }
    
    struct UpsertTests {
        @Test func upsertAndFetchById() async throws {
            let db = try await TestData.getSSHadowDb()

            let id = NSFileProviderItemIdentifier(UUID().uuidString)
            let parentId = NSFileProviderItemIdentifier(UUID().uuidString)
            let item = SSHItem(id: id, parentId: parentId, name: "hello.txt")

            try await db.upsert(item)
            let actual = try #require(await db.fetch(id: id))

            #expect(actual.id == id)
            #expect(actual.parentId == parentId)
            #expect(actual.name == "hello.txt")
        }

        @Test func upsertDuplicateIdUpdatesExistingItem() async throws {
            let db = try await TestData.getSSHadowDb()
            
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
        
        @Test func upsertMultipleItems() async throws {
            let db = try await TestData.getSSHadowDb()

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
    }
    
    struct ChunkTests {
        @Test func isChunkCachedReturnsFalseForNewItem() async throws {
            let db = try await TestData.getSSHadowDb()
            let itemId = NSFileProviderItemIdentifier(UUID().uuidString)

            #expect(await !db.isChunkCached(for: itemId, index: 0))
        }

        @Test func recordAndQueryChunk() async throws {
            let db = try await TestData.getSSHadowDb()
            let itemId = NSFileProviderItemIdentifier(UUID().uuidString)

            try await db.recordChunk(for: itemId, index: 3)

            #expect(await db.isChunkCached(for: itemId, index: 3))
            #expect(await !db.isChunkCached(for: itemId, index: 0))
        }

        @Test func recordChunkIsIdempotent() async throws {
            let db = try await TestData.getSSHadowDb()
            let itemId = NSFileProviderItemIdentifier(UUID().uuidString)

            try await db.recordChunk(for: itemId, index: 0)
            try await db.recordChunk(for: itemId, index: 0)

            #expect(await db.isChunkCached(for: itemId, index: 0))
        }

        @Test func chunksAreIsolatedPerItem() async throws {
            let db = try await TestData.getSSHadowDb()
            let item1 = NSFileProviderItemIdentifier(UUID().uuidString)
            let item2 = NSFileProviderItemIdentifier(UUID().uuidString)

            try await db.recordChunk(for: item1, index: 0)
            try await db.recordChunk(for: item2, index: 1)

            #expect(await db.isChunkCached(for: item1, index: 0))
            #expect(await !db.isChunkCached(for: item1, index: 1))
            #expect(await !db.isChunkCached(for: item2, index: 0))
            #expect(await db.isChunkCached(for: item2, index: 1))
        }

        @Test func deleteChunksRemovesAllForItem() async throws {
            let db = try await TestData.getSSHadowDb()
            let item1 = NSFileProviderItemIdentifier(UUID().uuidString)
            let item2 = NSFileProviderItemIdentifier(UUID().uuidString)

            try await db.recordChunk(for: item1, index: 0)
            try await db.recordChunk(for: item1, index: 1)
            try await db.recordChunk(for: item2, index: 0)
            try await db.deleteChunks(for: item1)

            #expect(await !db.isChunkCached(for: item1, index: 0))
            #expect(await !db.isChunkCached(for: item1, index: 1))
            #expect(await db.isChunkCached(for: item2, index: 0))
        }
    }
}
