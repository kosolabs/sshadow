import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH
import Testing

@testable import AgentKit

extension TestSandbox {
    fileprivate func getSession() async throws -> Session {
        let config = try config
        let ssh = try await SSHClient.connect(config: config)
        let sftp = try await ssh.sftp()
        let db = try await DomainDB.open(
            config: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let session = Session(
            config: config,
            ssh: ssh,
            sftp: sftp,
            db: db,
            sharedUrl: shared,
            signal: { _ in },
            transfers: Transfers(),
            pollInterval: nil
        )

        var folders: [NSFileProviderItemIdentifier] = [
            .rootContainer, .trashContainer,
        ]
        while !folders.isEmpty {
            let folder = folders.removeFirst()
            let items = try await session.list(for: folder)
            for item in items {
                if item.kind == .folder,
                    let flags = item.flags,
                    flags.contains(.executable)
                {
                    folders.append(item.id)
                }
            }
        }

        return session
    }
}

extension Collection {
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}

extension [Change] {
    fileprivate func split() -> (Set<Item>, Set<NSFileProviderItemIdentifier>) {
        var updates: Set<Item> = []
        var deletedIds: Set<NSFileProviderItemIdentifier> = []
        for change in self {
            switch change {
            case .update(let item):
                updates.insert(item)
            case .delete(let itemId):
                deletedIds.insert(NSFileProviderItemIdentifier(itemId))
            }
        }
        return (updates, deletedIds)
    }
}

extension Session {
    fileprivate func id(of path: String) async throws
        -> NSFileProviderItemIdentifier
    {
        var curr: NSFileProviderItemIdentifier = .rootContainer
        for name in path.split(separator: "/") {
            curr = try await child(of: curr, name: String(name))
        }
        return curr
    }

    fileprivate func item(at path: String) async throws -> Item {
        try await item(for: id(of: path))
    }
}

struct SessionTests {
    struct NameChildParentPathTests {
        @Test func nameReturnsFilenameForItem() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt")
            let session = try await sandbox.getSession()

            let fileId = try await session.child(name: "file.txt")
            let name = try await session.name(of: fileId)
            #expect(name == "file.txt")
        }

        @Test func nameReturnsFilenameForNestedItem() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "folder/file.txt")
            let session = try await sandbox.getSession()

            let folderId = try await session.child(name: "folder")
            let fileId = try await session.child(of: folderId, name: "file.txt")
            let name = try await session.name(of: fileId)
            #expect(name == "file.txt")
        }

        @Test func parentOfTopLevelItemIsRootContainer() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "folder")
            let session = try await sandbox.getSession()

            let topLevel = try await session.child(name: "folder")
            let parent = try await session.parent(of: topLevel)
            #expect(parent == .rootContainer)
        }

        @Test func parentOfItemInTrashIsTrashContainer() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: ".sshadow/trash/file.txt")
            let session = try await sandbox.getSession()

            let fileId = try await session.child(
                of: .trashContainer,
                name: "file.txt"
            )
            let parent = try await session.parent(of: fileId)
            #expect(parent == .trashContainer)
        }

        @Test func parentOfItemIsParentFolder() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "folder/file.txt")
            let session = try await sandbox.getSession()

            let folderId = try await session.child(name: "folder")
            let fileId = try await session.child(of: folderId, name: "file.txt")
            let parentId = try await session.parent(of: fileId)
            #expect(parentId == folderId)
        }

        @Test func parentOfDeeplyNestedItemIsImmediateParent() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "folder/subdir/file.txt")
            let session = try await sandbox.getSession()

            let folderId = try await session.child(name: "folder")
            let subdirId = try await session.child(of: folderId, name: "subdir")
            let fileId = try await session.child(of: subdirId, name: "file.txt")
            let parentId = try await session.parent(of: fileId)
            #expect(parentId == subdirId)
        }

        @Test func pathForRootContainerReturnsConfigPath() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let path = try await session.path(for: .rootContainer)
            #expect(path == sandbox.mount.path())
        }

        @Test func pathForItemReturnsCombinedPath() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "folder/file.txt")
            let session = try await sandbox.getSession()

            let folderId = try await session.child(name: "folder")
            let itemId = try await session.child(of: folderId, name: "file.txt")
            let path = try await session.path(for: itemId)
            #expect(path == "\(sandbox.mount.path())/folder/file.txt")
        }

        @Test func pathForNameInParentReturnsCombinedPath() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "folder/file.txt")
            let session = try await sandbox.getSession()

            let folderId = try await session.child(name: "folder")
            let path = try await session.path(
                for: "file.txt",
                parentId: folderId
            )
            #expect(path == "\(sandbox.mount.path())/folder/file.txt")
        }

        @Test func pathForNameInRootReturnsCombinedPath() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt")
            let session = try await sandbox.getSession()

            let path = try await session.path(
                for: "file.txt",
                parentId: .rootContainer
            )
            #expect(path == "\(sandbox.mount.path())/file.txt")
        }
    }

    struct ItemTests {
        @Test func itemForFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let contents = "Hello, World!"
            try sandbox.createFile(at: "file.txt", contents: contents)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "file.txt")
            let item = try await session.item(for: itemId)

            #expect(item.name == "file.txt")
            #expect(item.kind == .file)
            #expect(item.size == UInt64(contents.utf8.count))
            #expect(item.id == itemId)
        }

        @Test func itemForFolderSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "folder")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "folder")
            let item = try await session.item(for: itemId)

            #expect(item.name == "folder")
            #expect(item.kind == .folder)
        }

        @Test func itemForSymlinkSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "target.txt")
            try sandbox.createSymlink(at: "symlink.txt", target: "target.txt")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "symlink.txt")
            let item = try await session.item(for: itemId)

            #expect(item.name == "symlink.txt")
            #expect(item.kind == .symlink(target: "target.txt"))
        }

        @Test func itemHasCorrectParent() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "folder/file.txt", contents: "data")
            let session = try await sandbox.getSession()

            let folderId = try await session.child(name: "folder")
            let itemId = try await session.child(of: folderId, name: "file.txt")
            let item = try await session.item(for: itemId)

            #expect(item.parentId == folderId)
        }

        @Test func itemReturnsCachedSnapshotWhenWarm() async throws {
            let sandbox = TestSandbox()
            let original = "1"
            try sandbox.createFile(at: "refresh.txt", contents: original)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "refresh.txt")
            let updated = "22"
            try sandbox.createFile(at: "refresh.txt", contents: updated)

            let item = try await session.item(for: itemId)
            #expect(item.size == UInt64(original.utf8.count))
        }

        @Test func itemServedFromCacheAfterFileDeleted() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "ghost.txt", contents: "boo")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "ghost.txt")
            try sandbox.removeItem(at: "ghost.txt")

            let item = try await session.item(for: itemId)
            #expect(item.name == "ghost.txt")
            #expect(item.kind == .file)
        }
    }

    struct ListTests {
        @Test func listReturnsFilesFoldersAndSymlinks() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt", contents: "hello")
            try sandbox.createFolder(at: "folder")
            try sandbox.createSymlink(at: "link.txt", target: "file.txt")
            let session = try await sandbox.getSession()

            let items = try await session.list(for: .rootContainer)

            let file = try #require(
                items.first { $0.name == "file.txt" }
            )
            #expect(file.kind == .file)

            let folder = try #require(
                items.first { $0.name == "folder" }
            )
            #expect(folder.kind == .folder)

            let symlink = try #require(
                items.first { $0.name == "link.txt" }
            )
            #expect(symlink.kind == .symlink(target: "file.txt"))
        }

        @Test func listEmptyDirectoryReturnsEmpty() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let items = try await session.list(for: .rootContainer)

            #expect(items.isEmpty)
        }

        @Test func listEntriesHaveCorrectParent() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "folder/child.txt", contents: "data")
            let session = try await sandbox.getSession()

            let parentId = try await session.child(name: "folder")
            let items = try await session.list(for: parentId)

            let child = try #require(
                items.first { $0.name == "child.txt" }
            )
            #expect(child.parentId == parentId)
        }

        @Test func listPopulatesSnapshotInDb() async throws {
            let sandbox = TestSandbox()
            let contents = "Hello, World!"
            try sandbox.createFile(at: "file.txt", contents: contents)
            let session = try await sandbox.getSession()

            let items = try await session.list(for: .rootContainer)
            let listed = try #require(items.first { $0.name == "file.txt" })

            let item = try await session.item(for: listed.id)
            #expect(item.kind == .file)
            #expect(item.size == UInt64(contents.utf8.count))
            #expect(item.size == listed.size)
            #expect(item.flags == listed.flags)
            #expect(item.modifyTime == listed.modifyTime)
        }

        @Test func listPopulatesSnapshotForFolderAndSymlink() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir")
            try sandbox.createFile(at: "target.txt", contents: "hi")
            try sandbox.createSymlink(at: "link.txt", target: "target.txt")
            let session = try await sandbox.getSession()

            _ = try await session.list(for: .rootContainer)

            let item = try await session.item(at: "dir")
            #expect(item.kind == .folder)

            let symlink = try await session.item(at: "link.txt")
            #expect(symlink.kind == .symlink(target: "target.txt"))
        }

        @Test func listTrashWithOneFileMarksTrashEnumerated() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: ".sshadow/trash/file.txt")
            let session = try await sandbox.getSession()

            let items = try await session.list(for: .trashContainer)

            #expect(items.map(\.name) == ["file.txt"])
            #expect(try await session.item(for: .trashContainer).isEnumerated)
        }

        @Test func listEmptyTrashMarksTrashEnumerated() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: ".sshadow/trash")
            let session = try await sandbox.getSession()

            let items = try await session.list(for: .trashContainer)

            #expect(items.isEmpty)
            #expect(try await session.item(for: .trashContainer).isEnumerated)
        }

        @Test func listRootDoesNotIncludeSSHadowFolder() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: ".sshadow/trash")
            let session = try await sandbox.getSession()

            let items = try await session.list(for: .rootContainer)

            #expect(items.isEmpty)
        }

        @Test func listNonExistentTrashMarksTrashEnumerated() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let items = try await session.list(for: .trashContainer)

            #expect(items.isEmpty)
            #expect(try await session.item(for: .trashContainer).isEnumerated)
        }

        @Test func listStampsEnumeratedAt() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "leaf.txt")
            let session = try await sandbox.getSession()

            #expect(try await session.item(for: .trashContainer).isEnumerated)
        }

        @Test func listServesEmptyDirectoryFromCache() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "empty")
            let session = try await sandbox.getSession()

            let folderId = try await session.child(name: "empty")
            try sandbox.removeItem(at: "empty")

            let items = try await session.list(for: folderId)
            #expect(items.isEmpty)
        }

        @Test func listServesPopulatedDirectoryFromCache() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "folder/file.txt", contents: "hello")
            let session = try await sandbox.getSession()

            let folderId = try await session.child(name: "folder")
            try sandbox.removeItem(at: "folder/file.txt")

            let items = try await session.list(for: folderId)
            let file = try #require(items.first { $0.name == "file.txt" })
            #expect(file.kind == .file)
        }

        @Test func listServesSymlinkFromCacheWithTarget() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "target.txt", contents: "hi")
            try sandbox.createSymlink(at: "link.txt", target: "target.txt")
            let session = try await sandbox.getSession()

            try sandbox.removeItem(at: "link.txt")

            let items = try await session.list(for: .rootContainer)
            let symlink = try #require(items.first { $0.name == "link.txt" })
            #expect(symlink.kind == .symlink(target: "target.txt"))
        }

        @Test func listDoesNotReEnumerateEnumeratedFolder() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "folder")
            let session = try await sandbox.getSession()

            let folderId = try await session.child(name: "folder")
            try sandbox.createFile(at: "folder/sneaky.txt", contents: "boo")

            let items = try await session.list(for: folderId)

            #expect(items.isEmpty)
        }

        @Test func listThrowsForMissingNonTrashFolder() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let ghost = try await session.createDirectory(
                parentId: .rootContainer,
                name: "ghost"
            )
            try sandbox.removeItem(at: "ghost")

            await #expect(throws: AgentError.itemNotFound(ghost.id.rawValue)) {
                try await session.list(for: ghost.id)
            }
        }
    }

    struct ReconcileTests {
        let start: Date = Date(timeIntervalSince1970: 1_750_000_000)
        let end: Date = Date(timeIntervalSince1970: 1_760_000_000)

        @Test func reconcileNoChanges() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            try sandbox.createSymlink(at: "other/link.txt", target: "file.txt")
            let session = try await sandbox.getSession()

            let changes = try await session.reconcile()

            let (updates, deletedIds) = changes.split()
            #expect(updates == [])
            #expect(deletedIds == [])
        }

        @Test func reconcileFileCreated() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "dir/item.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            let changes = try await session.reconcile()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "item.txt")
            #expect(item.modifyTime == end)
            #expect(deletedIds == [])
        }

        @Test func reconcileFileSizeChanged() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "dir/item.txt", modifyDate: start)
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            let currValue = "curr"
            try sandbox.createFile(
                at: "dir/item.txt",
                contents: currValue,
                modifyDate: end
            )
            try sandbox.touch("dir", modifyDate: start)
            let changes = try await session.reconcile()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "item.txt")
            #expect(item.size == UInt64(currValue.count))
            #expect(deletedIds == [])
        }

        @Test func reconcileFilePermissionsChanged() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "dir/item.txt", modifyDate: start)
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.touch("dir/item.txt", permissions: 0o444)
            let changes = try await session.reconcile()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "item.txt")
            #expect(item.flags == [.readable])
            #expect(deletedIds == [])
        }

        @Test func reconcileFileDateModifiedChanged() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "dir/item.txt", modifyDate: start)
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "dir/item.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            let changes = try await session.reconcile()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "item.txt")
            #expect(item.modifyTime == end)
            #expect(deletedIds == [])
        }

        @Test func reconcileFileDeleted() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "dir/item.txt", modifyDate: start)
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            let fileId = try await session.id(of: "dir/item.txt")
            try sandbox.removeItem(at: "dir/item.txt")
            try sandbox.touch("dir", modifyDate: start)
            let changes = try await session.reconcile()

            let (updates, deletedIds) = changes.split()
            #expect(updates == [])
            #expect(deletedIds == [fileId])
        }

        @Test func reconcileFileMoved() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "dir/old.txt", modifyDate: start)
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            let oldId = try await session.id(of: "dir/old.txt")
            try sandbox.move(from: "dir/old.txt", to: "dir/new.txt")
            try sandbox.touch("dir", modifyDate: start)
            let changes = try await session.reconcile()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "new.txt")
            #expect(deletedIds == [oldId])
        }

        @Test func reconcileFolderCreated() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFolder(at: "dir/subdir", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            let changes = try await session.reconcile()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "subdir")
            #expect(item.modifyTime == end)
            #expect(deletedIds == [])
        }

        @Test func reconcileFolderDeleted() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir/subdir", modifyDate: start)
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            let fileId = try await session.id(of: "dir/subdir")
            try sandbox.removeItem(at: "dir/subdir")
            try sandbox.touch("dir", modifyDate: start)
            let changes = try await session.reconcile()

            let (updates, deletedIds) = changes.split()
            #expect(updates == [])
            #expect(deletedIds == [fileId])
        }

        @Test func reconcileFileReplacedWithFolder() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir/thing", modifyDate: start)
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            let fileId = try await session.id(of: "dir/thing")
            try sandbox.removeItem(at: "dir/thing")
            try sandbox.createFile(at: "dir/thing", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            let changes = try await session.reconcile()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "thing")
            #expect(item.modifyTime == end)
            #expect(deletedIds == [fileId])
        }

        @Test func reconcileSymlinkCreated() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "dir/target.txt", modifyDate: start)
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createSymlink(at: "dir/link.txt", target: "target.txt")
            try sandbox.touch("dir", modifyDate: start)
            let changes = try await session.reconcile()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "link.txt")
            #expect(deletedIds == [])
        }

        @Test func reconcileSymlinkDeleted() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "dir/target.txt", modifyDate: start)
            try sandbox.createSymlink(at: "dir/link.txt", target: "target.txt")
            try sandbox.touch("dir", modifyDate: start)
            let session = try await sandbox.getSession()

            let linkId = try await session.id(of: "dir/target.txt")
            try sandbox.removeItem(at: "dir/target.txt")
            try sandbox.touch("dir", modifyDate: start)
            let changes = try await session.reconcile()

            let (updates, deletedIds) = changes.split()
            #expect(updates == [])
            #expect(deletedIds == [linkId])
        }

        @Test func reconcileSymlinkRecreated() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "dir/old.txt", modifyDate: start)
            try sandbox.createFile(at: "dir/new.txt", modifyDate: start)
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            try sandbox.createSymlink(at: "dir/link.txt", target: "old.txt")
            try sandbox.touch("dir", modifyDate: start)
            let session = try await sandbox.getSession()

            let linkId = try await session.id(of: "dir/link.txt")
            try sandbox.createSymlink(at: "dir/link.txt", target: "new.txt")
            try sandbox.touch("dir", modifyDate: start)
            let changes = try await session.reconcile()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "link.txt")
            #expect(deletedIds == [linkId])
        }
    }

    struct PollChangesTests {
        let start: Date = Date(timeIntervalSince1970: 1_750_000_000)
        let end: Date = Date(timeIntervalSince1970: 1_760_000_000)

        @Test func pollWithNoChangesAccumulatesEmpty() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            try await session.poll()

            let (_, changes) = await session.changes(since: 0)
            #expect(changes == [])
        }

        @Test func pollSurfacesCreatedFile() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "dir/new.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.poll()

            let (_, changes) = await session.changes(since: 0)
            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "new.txt")
            #expect(deletedIds == [])
        }

        @Test func changesIsEmptyBeforeAnyPoll() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt")
            let session = try await sandbox.getSession()

            let (_, changes) = await session.changes(since: 0)
            #expect(changes == [])
        }

        @Test func changesAccumulatesAcrossMultiplePolls() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "dir/first.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.poll()

            try sandbox.createFile(at: "dir/second.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.poll()

            let (_, changes) = await session.changes(since: 0)
            let (updates, _) = changes.split()
            let names = Set(updates.map { $0.name })
            #expect(names == ["first.txt", "second.txt"])
        }

        @Test func changesFiltersByAnchor() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "dir/first.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.poll()

            try sandbox.createFile(at: "dir/second.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.poll()

            let (_, changes) = await session.changes(since: 1)
            let (updates, _) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "second.txt")
        }

        @Test func currentAnchorStartsAtZero() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            #expect(await session.currentAnchor == 0)
        }

        @Test func currentAnchorAdvancesOnPoll() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "dir/first.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.poll()
            #expect(await session.currentAnchor == 1)

            try sandbox.createFile(at: "dir/second.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.poll()
            #expect(await session.currentAnchor == 2)
        }

        @Test func currentAnchorDoesNotAdvanceWithoutChanges() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            try await session.poll()
            #expect(await session.currentAnchor == 0)

            try await session.poll()
            #expect(await session.currentAnchor == 0)
        }

        @Test func changesReturnsCurrentAnchor() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "dir/first.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.poll()

            try sandbox.createFile(at: "dir/second.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.poll()

            let (anchor, _) = await session.changes(since: 0)
            #expect(anchor == 2)
        }
    }

    struct SetAttributesTests {
        @Test func setFlagsSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "perms.txt", permissions: 0o400)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "perms.txt")
            try await session.setAttributes(for: itemId, flags: .rw)

            #expect(try sandbox.permissions(of: "perms.txt") == 0o600)
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func setModifyTimeSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "modify-time.txt", contents: "test")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "modify-time.txt")
            let date = Date(timeIntervalSince1970: 1_000_000)
            try await session.setAttributes(for: itemId, modifyTime: date)

            #expect(try sandbox.modifyDate(of: "modify-time.txt") == date)
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func setAccessTimeSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "access-time.txt", contents: "test")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "access-time.txt")
            let date = Date(timeIntervalSince1970: 2_000_000)
            try await session.setAttributes(for: itemId, accessTime: date)

            #expect(try sandbox.accessDate(of: "access-time.txt") == date)
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func setAttributesForMissingFileThrows() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "missing.txt", contents: "Hello!")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "missing.txt")
            try sandbox.removeItem(at: "missing.txt")

            await #expect(throws: AgentError.itemNotFound(itemId.rawValue)) {
                try await session.setAttributes(for: itemId, flags: .rw)
            }
        }
    }

    struct CreateDirectoryTests {
        @Test func createDirectorySucceeds() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let item = try await session.createDirectory(
                parentId: .rootContainer,
                name: "new-dir",
                mode: 0o755
            )

            #expect(item.name == "new-dir")
            #expect(item.kind == .folder)
            #expect(try sandbox.permissions(of: "new-dir") == 0o755)
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func createDirectoryWithIfExistsSucceedSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "existing-dir")
            let session = try await sandbox.getSession()

            let item = try await session.createDirectory(
                parentId: .rootContainer,
                name: "existing-dir",
                ifExists: .succeed
            )

            #expect(item.name == "existing-dir")
            #expect(item.kind == .folder)
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func createDirectoryWhenExistsThrows() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "already-exists")
            let session = try await sandbox.getSession()

            await #expect {
                try await session.createDirectory(
                    parentId: .rootContainer,
                    name: "already-exists"
                )
            } throws: { error in
                guard case AgentError.filenameCollision = error else {
                    return false
                }
                return true
            }
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func createDirectoryInsertsRowMatchingItemId() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let item = try await session.createDirectory(
                parentId: .rootContainer,
                name: "row-match-dir"
            )

            let lookedUpId = try await session.child(name: "row-match-dir")
            #expect(lookedUpId == item.id)
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func createDirectoryFailureLeavesNoRow() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "collide-dir")
            let session = try await sandbox.getSession()

            await #expect(throws: AgentError.filenameCollision) {
                _ = try await session.createDirectory(
                    parentId: .rootContainer,
                    name: "collide-dir"
                )
            }
            let changes = try await session.reconcile()
            #expect(changes == [])
        }
    }

    struct CreateSymlinkTests {
        @Test func createSymlinkSucceeds() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let item = try await session.createSymlink(
                parentId: .rootContainer,
                name: "link",
                target: "/etc/hosts"
            )

            #expect(item.name == "link")
            #expect(item.kind == .symlink(target: "/etc/hosts"))
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func createSymlinkInsertsRowMatchingItemId() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let item = try await session.createSymlink(
                parentId: .rootContainer,
                name: "link",
                target: "/dev/null"
            )

            let lookedUpId = try await session.child(name: "link")
            #expect(lookedUpId == item.id)
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func createSymlinkFailureLeavesNoRow() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "collide")
            let session = try await sandbox.getSession()

            await #expect(throws: (any Error).self) {
                _ = try await session.createSymlink(
                    parentId: .rootContainer,
                    name: "collide",
                    target: "/dev/null"
                )
            }
            let changes = try await session.reconcile()
            #expect(changes == [])
        }
    }

    struct MoveTests {
        @Test func moveRenamesFile() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "original.txt", contents: "hello")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "original.txt")

            try await session.move(
                itemId,
                toParent: .rootContainer,
                name: "renamed.txt"
            )

            let newId = try await session.child(name: "renamed.txt")
            #expect(itemId == newId)
            #expect(sandbox.exists(at: "renamed.txt"))
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func moveToNewParent() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt", contents: "hello")
            try sandbox.createFolder(at: "dest")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "file.txt")
            let destId = try await session.child(name: "dest")

            try await session.move(itemId, toParent: destId, name: "file.txt")

            let movedId = try await session.child(of: destId, name: "file.txt")
            #expect(itemId == movedId)
            #expect(sandbox.exists(at: "dest/file.txt"))
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func moveToNewParentAndRename() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "old.txt", contents: "hello")
            try sandbox.createFolder(at: "dest")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "old.txt")
            let destId = try await session.child(name: "dest")

            try await session.move(itemId, toParent: destId, name: "new.txt")

            let parent = try await session.parent(of: itemId)
            #expect(parent == destId)

            let name = try await session.name(of: itemId)
            #expect(name == "new.txt")
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func moveToMissingTrashCreatesTrashFolder() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt", contents: "hello")
            let session = try await sandbox.getSession()
            #expect(!sandbox.exists(at: ".sshadow/trash"))

            let itemId = try await session.child(name: "file.txt")
            try await session.move(
                itemId,
                toParent: .trashContainer,
                name: "file.txt"
            )

            #expect(!sandbox.exists(at: "file.txt"))
            #expect(sandbox.exists(at: ".sshadow/trash/file.txt"))
            let trashed = try await session.child(
                of: .trashContainer,
                name: "file.txt"
            )
            #expect(trashed == itemId)
        }
    }

    struct RemoveFileTests {
        @Test func removeFileSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "delete.txt")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "delete.txt")
            try await session.removeFile(for: itemId)

            #expect(!sandbox.exists(at: "delete.txt"))
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func removeFileFromFolderSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "folder/delete.txt")
            let session = try await sandbox.getSession()

            let folderId = try await session.child(name: "folder")
            let itemId = try await session.child(
                of: folderId,
                name: "delete.txt"
            )
            try await session.removeFile(for: itemId)

            #expect(!sandbox.exists(at: "folder/delete.txt"))
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func removeFileMissingThrows() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "missing.txt")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "missing.txt")
            try await session.removeFile(for: itemId)

            await #expect(throws: AgentError.itemNotFound(itemId)) {
                try await session.removeFile(for: itemId)
            }
            let changes = try await session.reconcile()
            #expect(changes == [])
        }
    }

    struct RemoveDirectoryTests {
        @Test func removeDirectorySucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "delete")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "delete")
            try await session.removeDirectory(for: itemId)

            #expect(!sandbox.exists(at: "delete"))
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func removeDirectoryWithContentsSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "non-empty/child.txt")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "non-empty")
            try await session.removeDirectory(for: itemId)

            #expect(!sandbox.exists(at: "non-empty"))
            let changes = try await session.reconcile()
            #expect(changes == [])
        }
    }

    struct UploadTests {
        @Test func uploadSmallFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let uploadUrl = sandbox.shared.appending(path: UUID().uuidString)
            let data = "Hello, World!\n"
            try data.write(to: uploadUrl, atomically: false, encoding: .utf8)

            let filename = "small-file.txt"
            let url = sandbox.getUrl(for: filename)
            let session = try await sandbox.getSession()

            let progress = Progress()
            let item = try await session.upload(
                parentId: .rootContainer,
                name: filename,
                file: uploadUrl,
                flags: .rw,
                progress: progress
            )
            let currId = try await session.child(name: filename)

            #expect(item.name == filename)
            #expect(item.size == UInt64(data.utf8.count))
            #expect(FileManager.default.fileExists(at: url))
            #expect(try String(contentsOf: url, encoding: .utf8) == data)
            #expect(progress.isFinished)
            #expect(try FileManager.default.permissions(of: url) == 0o600)
            #expect(currId == item.id)
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func uploadLargeFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let uploadUrl = sandbox.shared.appending(path: UUID().uuidString)
            let data = Data(count: 10_485_760)
            try data.write(to: uploadUrl)

            let filename = "large-file.txt"
            let url = sandbox.getUrl(for: filename)
            let session = try await sandbox.getSession()

            let progress = Progress()
            let item = try await session.upload(
                parentId: .rootContainer,
                name: filename,
                file: uploadUrl,
                flags: .rw,
                progress: progress
            )
            let currId = try await session.child(name: filename)

            #expect(item.name == filename)
            #expect(item.size == UInt64(data.count))
            #expect(FileManager.default.fileExists(at: url))
            #expect(try Data(contentsOf: url) == data)
            #expect(progress.isFinished)
            #expect(try FileManager.default.permissions(of: url) == 0o600)
            #expect(currId == item.id)
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func uploadFailureLeavesNoRow() async throws {
            let sandbox = TestSandbox()
            // Pre-create a directory at the upload target so opening it as a
            // file for writing fails.
            try sandbox.createFolder(at: "collide-upload")
            let session = try await sandbox.getSession()

            let uploadUrl = sandbox.shared.appending(path: UUID().uuidString)
            try Data("data".utf8).write(to: uploadUrl)

            await #expect(throws: (any Error).self) {
                _ = try await session.upload(
                    parentId: .rootContainer,
                    name: "collide-upload",
                    file: uploadUrl,
                    flags: .rw,
                    progress: Progress()
                )
            }
            let changes = try await session.reconcile()
            #expect(changes == [])
        }

        @Test func uploadCancelledThrowsUserCancelled() async throws {
            let sandbox = TestSandbox()
            let uploadUrl = sandbox.shared.appending(path: UUID().uuidString)
            let data = Data(count: 10_485_760)
            try data.write(to: uploadUrl)

            let session = try await sandbox.getSession()

            let progress = Progress()
            progress.cancel()

            await #expect(throws: AgentError.userCancelled) {
                _ = try await session.upload(
                    parentId: .rootContainer,
                    name: "cancelled.dat",
                    file: uploadUrl,
                    flags: .rw,
                    progress: progress
                )
            }
        }

        @Test func uploadEmptyFileToFolderSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "folder")
            let uploadUrl = sandbox.shared.appending(path: UUID().uuidString)
            try Data().write(to: uploadUrl)

            let url = sandbox.getUrl(for: "folder/file.txt")
            let session = try await sandbox.getSession()

            let progress = Progress()
            let folderId = try await session.child(name: "folder")
            let item = try await session.upload(
                parentId: folderId,
                name: "file.txt",
                file: uploadUrl,
                flags: .rw,
                progress: progress
            )
            let currId = try await session.child(of: folderId, name: "file.txt")

            #expect(item.name == "file.txt")
            #expect(item.size == 0)
            #expect(FileManager.default.fileExists(at: url))
            #expect(try Data(contentsOf: url).isEmpty)
            #expect(progress.isFinished)
            #expect(try FileManager.default.permissions(of: url) == 0o600)
            #expect(currId == item.id)
            let changes = try await session.reconcile()
            #expect(changes == [])
        }
    }

    struct DownloadTests {
        @Test func downloadSmallFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let data = "Hello, World!"
            try sandbox.createFile(at: "small-file.txt", contents: data)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "small-file.txt")
            let progress = Progress()
            let (url, item) = try await session.download(
                itemId: itemId,
                progress: progress
            )

            #expect(item.name == "small-file.txt")
            #expect(item.kind == .file)
            let size = try #require(item.size)
            #expect(size == data.count)
            #expect(try String(contentsOf: url, encoding: .utf8) == data)
            #expect(progress.isFinished)
        }

        @Test func downloadLargeFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let data = Data(count: 10_485_760)
            try sandbox.createFile(at: "large-file.dat", data: data)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "large-file.dat")
            let progress = Progress()
            let (url, item) = try await session.download(
                itemId: itemId,
                progress: progress
            )

            #expect(item.name == "large-file.dat")
            let size = try #require(item.size)
            #expect(size == data.count)
            #expect(try Data(contentsOf: url) == data)
            #expect(progress.isFinished)
        }

        @Test func downloadCancelledThrowsUserCancelled() async throws {
            let sandbox = TestSandbox()
            let data = Data(count: 10_485_760)
            try sandbox.createFile(at: "cancel.dat", data: data)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "cancel.dat")
            let progress = Progress()
            progress.cancel()

            await #expect(throws: AgentError.userCancelled) {
                _ = try await session.download(
                    itemId: itemId,
                    progress: progress
                )
            }
        }

        @Test func downloadEmptyFileSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "empty-file.txt", contents: "")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "empty-file.txt")
            let progress = Progress()
            let (url, item) = try await session.download(
                itemId: itemId,
                progress: progress
            )

            #expect(item.name == "empty-file.txt")
            #expect(item.size == 0)
            #expect(try Data(contentsOf: url).isEmpty)
            #expect(progress.isFinished)
        }
    }

    struct StreamTests {
        let chunkSize = File.defaultChunkSize

        @Test func streamSmallFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let data = Data(repeating: 0xAB, count: Int(chunkSize))
            try sandbox.createFile(at: "small.dat", data: data)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "small.dat")
            let progress = Progress()
            let (url, range) = try await session.stream(
                itemId: itemId,
                range: 0..<1,
                progress: progress
            )

            #expect(range == 0..<chunkSize)
            #expect(try Data(contentsOf: url) == data)
            #expect(progress.isFinished)
        }

        @Test func streamEmptyFileSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "empty.dat", data: Data())
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "empty.dat")
            let progress = Progress()
            let (url, range) = try await session.stream(
                itemId: itemId,
                range: 0..<0,
                progress: progress
            )

            #expect(range == 0..<0)
            #expect(try Data(contentsOf: url).isEmpty)
            #expect(progress.isFinished)
        }

        @Test func streamExpandsRangeToChunkBoundary() async throws {
            let sandbox = TestSandbox()
            let data = Data(count: Int(chunkSize) * 2)
            try sandbox.createFile(at: "two-chunk-range.dat", data: data)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "two-chunk-range.dat")
            let requestedRange = (chunkSize + 100)..<(chunkSize + 200)
            let (_, range) = try await session.stream(
                itemId: itemId,
                range: requestedRange,
                progress: Progress()
            )

            #expect(range == chunkSize..<(chunkSize * 2))
            #expect(range.lowerBound <= requestedRange.lowerBound)
            #expect(range.upperBound >= requestedRange.upperBound)
        }

        @Test func streamWritesDataAtCorrectOffset() async throws {
            let sandbox = TestSandbox()
            // Two-chunk file: first chunk 0xAA, second chunk 0xBB
            let data =
                Data(repeating: 0xAA, count: Int(chunkSize))
                + Data(repeating: 0xBB, count: Int(chunkSize))
            try sandbox.createFile(at: "offset.dat", data: data)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "offset.dat")
            let requestedRange = (chunkSize + 100)..<(chunkSize + 200)
            let (url, _) = try await session.stream(
                itemId: itemId,
                range: requestedRange,
                progress: Progress()
            )

            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: requestedRange.lowerBound)
            let count = Int(
                requestedRange.upperBound - requestedRange.lowerBound
            )
            let actual = try handle.read(upToCount: Int(count))
            let expected = Data(repeating: 0xBB, count: count)

            #expect(actual == expected)
        }
    }

    struct WithFileTests {
        @Test func withFileReadSucceeds() async throws {
            let sandbox = TestSandbox()
            let contents = "Hello, World!"
            try sandbox.createFile(at: "read-file.txt", contents: contents)
            let session = try await sandbox.getSession()

            let data = try await session.withFile(
                for: session.child(name: "read-file.txt"),
                accessType: .readOnly
            ) { fp in
                try await fp.read()
            }

            #expect(String(data: data, encoding: .utf8) == contents)
        }

        @Test func withFileMissingFileThrowsNoSuchItem() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "missing.txt", contents: "Hello!")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "missing.txt")
            try sandbox.removeItem(at: "missing.txt")

            await #expect(throws: AgentError.itemNotFound(itemId.rawValue)) {
                try await session.withFile(for: itemId, accessType: .readOnly) {
                    _ in
                }
            }
        }
    }

    struct WithDirectoryTests {
        @Test func withDirectoryListsEntries() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "folder/file.txt", contents: "hello")
            try sandbox.createFolder(at: "folder/subfolder")
            let session = try await sandbox.getSession()

            let dirId = try await session.child(name: "folder")
            let names = try await session.withDirectory(for: dirId) { dir in
                var names: [String] = []
                for try await attrs in dir {
                    if let name = attrs.name {
                        names.append(name)
                    }
                }
                return names
            }

            #expect(names.contains("file.txt"))
            #expect(names.contains("subfolder"))
        }

        @Test func withDirectoryEmptyDirYieldsNothing() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "empty")
            let session = try await sandbox.getSession()

            let dirId = try await session.child(name: "empty")
            let count = try await session.withDirectory(for: dirId) { dir in
                var count = 0
                for try await _ in dir {
                    count += 1
                }
                return count
            }

            #expect(count == 0)
        }
    }
}
