import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH
import TestKit
import Testing

@testable import CoreKit

private func text(
    _ contents: String,
    named name: String = ".sshadowignore"
) -> IgnoreFile {
    IgnoreFile(
        name: name,
        content: .loaded(
            contents,
            version: IgnoreFile.Version(modifyTime: .distantPast, size: 0)
        )
    )
}

private func unresolved() -> IgnoreFile {
    IgnoreFile(name: ".sshadowignore", content: .unresolved)
}

private func folder(_ path: String, _ files: IgnoreFile...) -> IgnoreFolder {
    IgnoreFolder(path: path, files: files)
}

extension TestSandbox {
    fileprivate func getSession(
        idleTimeProvider:
            @escaping Session.IdleTimeProvider = SystemIdle.duration,
        connectionLostHandler:
            @escaping Session.ConnectionLostHandler = { _ in },
        ignoreRulesChangedHandler:
            @escaping Session.Signal = {}
    ) async throws -> Session {
        try await makeSession(
            idleTimeProvider: idleTimeProvider,
            connectionLostHandler: connectionLostHandler,
            ignoreRulesChangedHandler: ignoreRulesChangedHandler
        ).session
    }

    @MainActor
    fileprivate func fileEvents(count: Int) async -> [String] {
        let messages = { [events] in
            events.value.filter { $0.category == .file }.map(\.message)
        }
        await expect(eventually: { messages().count >= count })
        return messages()
    }

    // Like `getSession`, but also hands back the underlying `SSHClient` so a
    // test can drop the transport out from under the session.
    fileprivate func makeSession(
        idleTimeProvider:
            @escaping Session.IdleTimeProvider = SystemIdle.duration,
        connectionLostHandler:
            @escaping Session.ConnectionLostHandler = { _ in },
        ignoreRulesChangedHandler:
            @escaping Session.Signal = {}
    ) async throws -> (session: Session, ssh: SSHClient) {
        let config = try config
        let (ssh, sftp) = try await withConnectRetries {
            () async throws(ConnectionError) -> (SSHClient, SFTPClient) in
            try await SSHClient.connect(config: config)
        }
        let db = try await DomainDB.open(
            config: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let session = Session(
            config: config,
            ssh: ssh,
            sftp: sftp,
            db: db,
            groupUrl: url(in: .group),
            changesDetectedHandler: {},
            ignoreRulesChangedHandler: ignoreRulesChangedHandler,
            connectionLostHandler: connectionLostHandler,
            idleTimeProvider: idleTimeProvider,
            materializedItems: { [materializedItems] in
                try materializedItems.enumerator()
            },
            evictItem: { [materializedItems] in
                try materializedItems.evict($0)
            },
            transfers: Transfers(),
            events: events
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

        return (session, ssh)
    }
}

/// Blocks the first `wait()` until `open()`; later calls pass through.
private actor Latch {
    private var waiter: CheckedContinuation<Void, Never>?
    private var used = false

    func wait() async {
        guard !used else { return }
        used = true
        await withCheckedContinuation { waiter = $0 }
    }

    func open() {
        used = true
        waiter?.resume()
        waiter = nil
    }
}

private func waitUntilOutstanding(
    _ session: Session,
    timeout: Duration = .seconds(10),
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let deadline = ContinuousClock.now + timeout
    while await session.outstanding == 0 {
        guard ContinuousClock.now < deadline else {
            Issue.record(
                "No operation became outstanding within \(timeout)",
                sourceLocation: sourceLocation
            )
            return
        }
        try await Task.sleep(for: .milliseconds(1))
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

extension TestSandbox {
    fileprivate enum Thing {
        case file(path: String, contents: String)
        case link(path: String, target: String)
    }

    @discardableResult
    fileprivate func createPackage(
        at root: String,
        in location: TestSandbox.Location = .remote,
        files: [Thing] = [.file(path: "TXT.rtf", contents: "{\rtf1 hello}")]
    ) throws -> URL {
        let url = try createFolder(at: root, in: location)
        for file in files {
            switch file {
            case .file(let path, let contents):
                try createFile(
                    at: "\(root)/\(path)",
                    in: location,
                    contents: contents
                )
            case .link(let path, let target):
                try createSymlink(
                    at: "\(root)/\(path)",
                    in: location,
                    target: target
                )
            }
        }
        return url
    }
}

extension TestSandbox {
    fileprivate func stagedUploads() throws -> [String] {
        let url = url(for: ".sshadow/uploads")
        guard FileManager.default.fileExists(at: url) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: url.path)
    }
}

private func contents(of url: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for entry in try Manifest(from: url).entries {
        if case .file = entry.kind {
            result[entry.path] = try Data(contentsOf: entry.url(under: url))
        }
    }
    return result
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
            #expect(path == sandbox.path(in: .remote))
        }

        @Test func pathForItemReturnsCombinedPath() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "folder/file.txt")
            let session = try await sandbox.getSession()

            let folderId = try await session.child(name: "folder")
            let itemId = try await session.child(of: folderId, name: "file.txt")
            let path = try await session.path(for: itemId)
            #expect(path == sandbox.path(for: "folder/file.txt", in: .remote))
        }

        @Test func pathForNameInParentReturnsCombinedPath() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "folder/file.txt")
            let session = try await sandbox.getSession()

            let folderId = try await session.child(name: "folder")
            let path = try await session.path(for: "file.txt", in: folderId)
            #expect(path == sandbox.path(for: "folder/file.txt", in: .remote))
        }

        @Test func pathForNameInRootReturnsCombinedPath() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt")
            let session = try await sandbox.getSession()

            let path = try await session.path(
                for: "file.txt",
                in: .rootContainer
            )
            #expect(path == sandbox.path(for: "file.txt", in: .remote))
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
            #expect(item.size == nil)
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
        @Test func listReportsPackageKind() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "Doc.rtfd/TXT.rtf", contents: "rtf")
            let session = try await sandbox.getSession()

            let items = try await session.list(for: .rootContainer)

            let package = try #require(items.only)
            #expect(package.name == "Doc.rtfd")
            #expect(package.kind == .package)
        }

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
            #expect(item.size == nil)

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
            try sandbox.createFolder(at: "ghost")
            _ = try await session.reconcileAll()
            let ghost = try await session.child(name: "ghost")
            try sandbox.removeItem(at: "ghost")

            await #expect(throws: CoreError.itemNotFound(ghost.rawValue)) {
                try await session.list(for: ghost)
            }
        }
    }

    struct ListIgnoreTests {
        @Test func listOmitsIgnoredEntries() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(
                at: ".sshadowignore",
                contents: "build/\n*.log\n"
            )
            try sandbox.createFolder(at: "build")
            try sandbox.createFile(at: "debug.log")
            try sandbox.createFile(at: "keep.txt")
            let session = try await sandbox.getSession()

            let items = try await session.list(for: .rootContainer)

            #expect(Set(items.map(\.name)) == [".sshadowignore", "keep.txt"])
        }

        @Test func nestedIgnoreFileAppliesToItsDirectory() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "src/.sshadowignore", contents: "*.o\n")
            try sandbox.createFile(at: "src/a.o")
            try sandbox.createFile(at: "b.o")
            let session = try await sandbox.getSession()
            let srcId = try await session.child(name: "src")

            let root = try await session.list(for: .rootContainer)
            let src = try await session.list(for: srcId)

            #expect(Set(root.map(\.name)) == ["src", "b.o"])
            #expect(Set(src.map(\.name)) == [".sshadowignore"])
        }

        @Test func newlyIgnoredMaterializedItemsStayOnReconcile() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: ".sshadowignore", contents: "*.log\n")
            try sandbox.createFile(at: "a.txt")
            let session = try await sandbox.getSession()
            let aId = try await session.child(name: "a.txt")
            sandbox.materializedItems.materialize(aId)

            try sandbox.createFile(at: ".sshadowignore", contents: "*.txt\n")
            try sandbox.createFile(at: "b.log")
            let changes = try await session.reconcileAll()
            let items = try await session.list(for: .rootContainer)

            #expect(!changes.contains(.delete(itemId: aId.rawValue)))
            #expect(
                Set(items.map(\.name)) == [".sshadowignore", "a.txt", "b.log"]
            )
        }

        @Test func remoteEditsToIgnoredWatchedFileAreSkipped() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "b.txt", contents: "b")
            let session = try await sandbox.getSession()
            let bId = try await session.child(name: "b.txt")
            sandbox.materializedItems.materialize(bId)
            await session.watch(itemId: bId)

            try sandbox.createFile(at: ".sshadowignore", contents: "b.txt\n")
            _ = try await session.reconcileAll()
            try sandbox.createFile(at: "b.txt", contents: "remote edit")
            let changes = try await session.reconcileWatched()

            #expect(changes == [])
        }

        @Test func remoteRuleChangeCallsHandler() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: ".sshadowignore", contents: "*.log\n")

            try await confirmation { called in
                let session = try await sandbox.getSession(
                    ignoreRulesChangedHandler: { called() }
                )
                try sandbox.createFile(
                    at: ".sshadowignore",
                    contents: "*.tmp\n"
                )
                _ = try await session.reconcileAll()
            }
        }

        @Test func listingSkipsIgnoreFileWithSameVersion() async throws {
            let sandbox = TestSandbox()
            let modified = Date(timeIntervalSince1970: 1_000_000)
            try sandbox.createFile(
                at: ".sshadowignore",
                contents: "*.log\n",
                modifyDate: modified
            )
            try sandbox.createFile(at: "a.log")
            try sandbox.createFile(at: "a.tmp")
            let session = try await sandbox.getSession()
            _ = try await session.list(for: .rootContainer)

            try sandbox.createFile(
                at: ".sshadowignore",
                contents: "*.tmp\n",
                modifyDate: modified
            )
            let items = try await session.list(for: .rootContainer)

            #expect(Set(items.map(\.name)) == [".sshadowignore", "a.tmp"])
        }

        @Test func pollRereadsChangedIgnoreFile() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: ".sshadowignore", contents: "*.log\n")
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: ".sshadowignore", contents: "*.tmp\n")
            _ = try await session.reconcileAll()
            let files = [folder("", unresolved())]
            _ = try await session.createSymlink(
                "a.log",
                in: .rootContainer,
                target: "/dev/null",
                snapshot: files
            )
            await #expect(throws: CoreError.ignored) {
                try await session.createSymlink(
                    "a.tmp",
                    in: .rootContainer,
                    target: "/dev/null",
                    snapshot: files
                )
            }

            #expect(sandbox.exists(at: "a.log"))
            #expect(!sandbox.exists(at: "a.tmp"))
        }

        @Test func ignoredRemoteAdditionIsNoChange() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: ".sshadowignore", contents: "*.log\n")
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "new.log")
            let changes = try await session.reconcileAll()

            #expect(changes == [])
        }

        @Test func trashIsNotFiltered() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: ".sshadowignore", contents: "*.log\n")
            try sandbox.createFile(at: ".sshadow/trash/old.log")
            let session = try await sandbox.getSession()

            let items = try await session.list(for: .trashContainer)

            #expect(items.map(\.name) == ["old.log"])
        }

        @Test func uploadUsesListedRemoteIgnoreFile() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: ".sshadowignore", contents: "build/\n")
            let session = try await sandbox.getSession()
            try sandbox.removeItem(at: ".sshadowignore")

            await #expect(throws: CoreError.ignored) {
                try await session.createDirectory(
                    "build",
                    in: .rootContainer,
                    snapshot: [folder("", unresolved())]
                )
            }

            #expect(!sandbox.exists(at: "build"))
        }
    }

    struct HideDatalessTests {
        @Test func newlyIgnoredDatalessFileIsHiddenOnReconcile() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "a.txt")
            let session = try await sandbox.getSession()
            let aId = try await session.child(name: "a.txt")

            try sandbox.createFile(at: ".sshadowignore", contents: "a.txt\n")
            let changes = try await session.reconcileAll()
            let items = try await session.list(for: .rootContainer)

            #expect(changes.contains(.delete(itemId: aId.rawValue)))
            #expect(Set(items.map(\.name)) == [".sshadowignore"])
            #expect(sandbox.exists(at: "a.txt"))
        }

        @Test func ignoredItemsStayWhenMaterializedSetIsUnavailable()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "a.txt")
            let session = try await sandbox.getSession()
            let aId = try await session.child(name: "a.txt")

            try sandbox.createFile(at: ".sshadowignore", contents: "a.txt\n")
            sandbox.materializedItems.failNext(1)
            let changes = try await session.reconcileAll()

            #expect(!changes.contains(.delete(itemId: aId.rawValue)))
            #expect(try await session.child(name: "a.txt") == aId)
        }

        @Test func newlyIgnoredDatalessWatchedFileIsHidden() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "a.txt")
            try sandbox.createFile(at: "other.txt")
            let session = try await sandbox.getSession()
            let aId = try await session.child(name: "a.txt")
            let otherId = try await session.child(name: "other.txt")
            await session.watch(itemId: aId)

            try await session.removeFile(
                for: otherId,
                snapshot: [folder("", text("a.txt\n"))]
            )
            let changes = try await session.reconcileWatched()

            #expect(changes == [.delete(itemId: aId.rawValue)])
        }

        @Test func newlyIgnoredDatalessFolderIsHidden() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "data/a.txt")
            let session = try await sandbox.getSession()
            let dataId = try await session.child(name: "data")

            try sandbox.createFile(at: ".sshadowignore", contents: "data/\n")
            let changes = try await session.reconcileAll()

            #expect(changes.contains(.delete(itemId: dataId.rawValue)))
            #expect(sandbox.exists(at: "data/a.txt"))
        }

        @Test func newlyIgnoredMaterializedFolderHidesOnlyDatalessChildren()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "data/read.txt")
            try sandbox.createFile(at: "data/unread.txt")
            let session = try await sandbox.getSession()
            let dataId = try await session.child(name: "data")
            _ = try await session.list(for: dataId)
            let readId = try await session.child(of: dataId, name: "read.txt")
            let unreadId = try await session.child(
                of: dataId,
                name: "unread.txt"
            )
            sandbox.materializedItems.materialize(dataId, readId)

            try sandbox.createFile(at: ".sshadowignore", contents: "data/\n")
            let changes = try await session.reconcileAll()
            let children = try await session.list(for: dataId)

            #expect(changes.contains(.delete(itemId: unreadId.rawValue)))
            #expect(!changes.contains(.delete(itemId: dataId.rawValue)))
            #expect(!changes.contains(.delete(itemId: readId.rawValue)))
            #expect(children.map(\.name) == ["read.txt"])
            #expect(sandbox.materializedItems.evicted.isEmpty)
        }

        @Test func newlyIgnoredFolderWithNothingDownloadedIsHidden()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "data/a.txt")
            let session = try await sandbox.getSession()
            let dataId = try await session.child(name: "data")
            _ = try await session.list(for: dataId)
            let aId = try await session.child(of: dataId, name: "a.txt")
            sandbox.materializedItems.materialize(dataId)

            try sandbox.createFile(at: ".sshadowignore", contents: "data/\n")
            let changes = try await session.reconcileAll()
            let (anchor, _) = await session.changes(since: 0)
            await session.refreshMaterialized().value
            let (_, evictionChanges) = await session.changes(since: anchor)

            #expect(changes.contains(.delete(itemId: aId.rawValue)))
            #expect(sandbox.materializedItems.evicted == [dataId])
            #expect(evictionChanges == [.delete(itemId: dataId.rawValue)])
            await #expect(throws: CoreError.itemNotFound) {
                try await session.child(name: "data")
            }
        }

        @Test func ignoredFolderStaysWhenEvictionIsRefused() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "data/a.txt")
            let session = try await sandbox.getSession()
            let dataId = try await session.child(name: "data")
            _ = try await session.list(for: dataId)
            sandbox.materializedItems.materialize(dataId)
            sandbox.materializedItems.refuseEviction()

            try sandbox.createFile(at: ".sshadowignore", contents: "data/\n")
            _ = try await session.reconcileAll()
            let (anchor, _) = await session.changes(since: 0)
            await session.refreshMaterialized().value
            let (_, changes) = await session.changes(since: anchor)

            #expect(changes.isEmpty)
            #expect(try await session.child(name: "data") == dataId)
        }

        @Test func evictingIgnoredFileHidesIt() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "a.txt")
            let session = try await sandbox.getSession()
            let aId = try await session.child(name: "a.txt")
            sandbox.materializedItems.materialize(aId)
            try sandbox.createFile(at: ".sshadowignore", contents: "a.txt\n")
            _ = try await session.reconcileAll()
            let (anchor, _) = await session.changes(since: 0)

            sandbox.materializedItems.dematerialize(aId)
            await session.refreshMaterialized().value
            let (_, changes) = await session.changes(since: anchor)

            #expect(changes == [.delete(itemId: aId.rawValue)])
            #expect(sandbox.materializedItems.evicted.isEmpty)
            await #expect(throws: CoreError.itemNotFound) {
                try await session.child(name: "a.txt")
            }
        }

        @Test func evictingLastFileInsideIgnoredFolderHidesBoth()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "data/a.txt")
            let session = try await sandbox.getSession()
            let dataId = try await session.child(name: "data")
            _ = try await session.list(for: dataId)
            let aId = try await session.child(of: dataId, name: "a.txt")
            sandbox.materializedItems.materialize(dataId, aId)
            try sandbox.createFile(at: ".sshadowignore", contents: "data/\n")
            _ = try await session.reconcileAll()
            let (anchor, _) = await session.changes(since: 0)

            sandbox.materializedItems.dematerialize(aId)
            await session.refreshMaterialized().value
            let (fileAnchor, fileChanges) = await session.changes(since: anchor)
            await session.refreshMaterialized().value
            let (_, folderChanges) = await session.changes(since: fileAnchor)

            #expect(fileChanges == [.delete(itemId: aId.rawValue)])
            #expect(sandbox.materializedItems.evicted == [dataId])
            #expect(folderChanges == [.delete(itemId: dataId.rawValue)])
            #expect(
                await sandbox.fileEvents(count: 5) == [
                    "Ignore rules changed in Root",
                    #"Evicted "data/a.txt""#,
                    #"Hide ignored "data/a.txt""#,
                    #"Evicted "data""#,
                    #"Hide ignored "data""#,
                ]
            )
        }

        @Test func evictingSyncedFileKeepsIt() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "a.txt")
            let session = try await sandbox.getSession()
            let aId = try await session.child(name: "a.txt")
            sandbox.materializedItems.materialize(aId)
            await session.refreshMaterialized().value
            let (anchor, _) = await session.changes(since: 0)

            sandbox.materializedItems.dematerialize(aId)
            await session.refreshMaterialized().value
            let (_, changes) = await session.changes(since: anchor)

            #expect(changes.isEmpty)
            #expect(try await session.child(name: "a.txt") == aId)
            #expect(
                await sandbox.fileEvents(count: 1) == [#"Evicted "a.txt""#]
            )
        }

        @Test func downloadRefusesIgnoredItem() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "a.txt")
            let session = try await sandbox.getSession()
            let aId = try await session.child(name: "a.txt")
            sandbox.materializedItems.materialize(aId)
            try sandbox.createFile(at: ".sshadowignore", contents: "a.txt\n")
            _ = try await session.reconcileAll()

            await #expect(throws: CoreError.itemNotFound) {
                _ = try await session.download(
                    itemId: aId,
                    progress: Progress()
                )
            }
        }
    }

    struct ProviderTests {
        @Test func startedSessionRetriesIgnoredItems() async throws {
            let sandbox = TestSandbox()
            let config = try sandbox.config

            try await confirmation { called in
                let provider = try await Session.provider(
                    domainDb: DomainDB.open(
                        config: ModelConfiguration(isStoredInMemoryOnly: true)
                    ),
                    groupUrl: sandbox.url(in: .group),
                    signalChanges: { _ in },
                    retryIgnored: { if $0.id == config.id { called() } },
                    materializedItems: { _ in
                        try sandbox.materializedItems.enumerator()
                    },
                    evictItem: { _, itemId in
                        try sandbox.materializedItems.evict(itemId)
                    },
                    transfers: Transfers(),
                    events: Events()
                )
                let session = try await withConnectRetries {
                    () async throws(ConnectionError) -> Session in
                    try await provider(config) { _ in }
                }
                await session.start(pollInterval: nil)
                await session.close()
            }
        }

        @Test func startedSessionLoadsMaterializedItems() async throws {
            let sandbox = TestSandbox()
            let config = try sandbox.config
            let store = sandbox.materializedItems
            let provider = try await Session.provider(
                domainDb: DomainDB.open(
                    config: ModelConfiguration(isStoredInMemoryOnly: true)
                ),
                groupUrl: sandbox.url(in: .group),
                signalChanges: { _ in },
                retryIgnored: { _ in },
                materializedItems: { materializedConfig in
                    #expect(materializedConfig.id == config.id)
                    return try store.enumerator()
                },
                evictItem: { _, itemId in try store.evict(itemId) },
                transfers: Transfers(),
                events: Events()
            )
            let session = try await withConnectRetries {
                () async throws(ConnectionError) -> Session in
                try await provider(config) { _ in }
            }

            #expect(store.created == 0)

            await session.start(pollInterval: nil)
            let deadline = ContinuousClock.now + .seconds(10)
            while store.reloads == 0 {
                try #require(ContinuousClock.now < deadline)
                try await Task.sleep(for: .milliseconds(1))
            }
            await session.close()
        }
    }

    struct ReconcileAllTests {
        let start: Date = Date(timeIntervalSince1970: 1_750_000_000)
        let end: Date = Date(timeIntervalSince1970: 1_760_000_000)

        @Test func reconcileNoChanges() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            try sandbox.createSymlink(at: "other/link.txt", target: "file.txt")
            let session = try await sandbox.getSession()

            let changes = try await session.reconcileAll()

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
            let changes = try await session.reconcileAll()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "item.txt")
            #expect(item.modifyTime == end)
            #expect(deletedIds == [])
        }

        @Test func reconcileIgnoresChangesInsidePackage() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "Doc.rtfd/TXT.rtf", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "Doc.rtfd/new.rtf", modifyDate: end)
            try sandbox.touch("Doc.rtfd", modifyDate: start)
            let changes = try await session.reconcileAll()

            let (updates, deletedIds) = changes.split()
            #expect(updates == [])
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
            let changes = try await session.reconcileAll()

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
            let changes = try await session.reconcileAll()

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
            let changes = try await session.reconcileAll()

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
            let changes = try await session.reconcileAll()

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
            let changes = try await session.reconcileAll()

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
            let changes = try await session.reconcileAll()

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
            let changes = try await session.reconcileAll()

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
            let changes = try await session.reconcileAll()

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
            let changes = try await session.reconcileAll()

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
            let changes = try await session.reconcileAll()

            let (updates, deletedIds) = changes.split()
            #expect(updates == [])
            #expect(deletedIds == [linkId])
        }

        @Test func reconcileSymlinkDateModifiedChanged() async throws {
            let sandbox = TestSandbox()
            try sandbox.createSymlink(
                at: "dir/broken.txt",
                target: "missing.txt",
                modifyDate: start
            )
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.touch("dir/broken.txt", modifyDate: end)
            let changes = try await session.reconcileAll()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "broken.txt")
            #expect(item.modifyTime == end)
            #expect(deletedIds == [])
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
            let changes = try await session.reconcileAll()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "link.txt")
            #expect(deletedIds == [linkId])
        }

        @Test func reconcileInvalidatesCachedFileContent() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(
                at: "dir/item.txt",
                contents: "old",
                modifyDate: start
            )
            try sandbox.createFile(at: "other/file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            let itemId = try await session.id(of: "dir/item.txt")
            let (warmUrl, _) = try await session.stream(
                itemId: itemId,
                range: 0..<1,
                progress: Progress()
            )
            #expect(try String(contentsOf: warmUrl, encoding: .utf8) == "old")

            try sandbox.createFile(
                at: "dir/item.txt",
                contents: "new",
                modifyDate: end
            )
            try sandbox.touch("dir", modifyDate: start)
            _ = try await session.reconcileAll()

            let (freshUrl, _) = try await session.stream(
                itemId: itemId,
                range: 0..<1,
                progress: Progress()
            )
            #expect(try String(contentsOf: freshUrl, encoding: .utf8) == "new")
        }
    }

    struct PollAllChangesTests {
        let start: Date = Date(timeIntervalSince1970: 1_750_000_000)
        let end: Date = Date(timeIntervalSince1970: 1_760_000_000)

        @Test func pollWithNoChangesAccumulatesEmpty() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            try await session.pollAll()

            let (_, changes) = await session.changes(since: 0)
            #expect(changes == [])
        }

        @Test func pollSurfacesCreatedFile() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "dir/new.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.pollAll()

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
            try await session.pollAll()

            try sandbox.createFile(at: "dir/second.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.pollAll()

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
            try await session.pollAll()
            let firstAnchor = await session.anchor

            try sandbox.createFile(at: "dir/second.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.pollAll()

            let (_, changes) = await session.changes(since: firstAnchor)
            let (updates, _) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "second.txt")
        }

        @Test func currentAnchorStartsAtZero() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            #expect(await session.anchor == 0)
        }

        @Test func currentAnchorAdvancesOnPoll() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "dir/first.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.pollAll()
            let firstAnchor = await session.anchor
            #expect(firstAnchor > 0)

            try sandbox.createFile(at: "dir/second.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.pollAll()
            #expect(await session.anchor > firstAnchor)
        }

        @Test func currentAnchorDoesNotAdvanceWithoutChanges() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            try await session.pollAll()
            #expect(await session.anchor == 0)

            try await session.pollAll()
            #expect(await session.anchor == 0)
        }

        @Test func changesReturnsCurrentAnchor() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "dir/first.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.pollAll()

            try sandbox.createFile(at: "dir/second.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.pollAll()

            let (anchor, _) = await session.changes(since: 0)
            #expect(anchor == (await session.anchor))
        }

        @Test func changesTruncatesAcknowledgedButKeepsUnread() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "dir/first.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.pollAll()
            let firstAnchor = await session.anchor

            try sandbox.createFile(at: "dir/second.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            try await session.pollAll()

            // Acknowledging through firstAnchor drops the first batch but keeps
            // the unread second one.
            _ = await session.changes(since: firstAnchor)

            let (_, again) = await session.changes(since: firstAnchor)
            let (updates, _) = again.split()
            #expect(updates.map { $0.name } == ["second.txt"])
        }
    }

    struct ReconcileWatchedTests {
        let start: Date = Date(timeIntervalSince1970: 1_750_000_000)
        let end: Date = Date(timeIntervalSince1970: 1_760_000_000)

        @Test func reconcileWatchedWithNothingWatchedReturnsEmpty()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            try sandbox.createFile(at: "dir/new.txt", modifyDate: end)
            try sandbox.touch("dir", modifyDate: start)
            let changes = try await session.reconcileWatched()

            #expect(changes == [])
        }

        @Test func reconcileWatchedSurfacesChangeInWatchedFolder()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            let dirId = try await session.child(name: "dir")
            await session.watch(itemId: dirId)

            try sandbox.createFile(at: "dir/new.txt", modifyDate: end)
            let changes = try await session.reconcileWatched()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "new.txt")
            #expect(deletedIds == [])
        }

        @Test func reconcileWatchedSurfacesDeletionInWatchedFolder()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "dir/item.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            let dirId = try await session.child(name: "dir")
            await session.watch(itemId: dirId)

            let fileId = try await session.id(of: "dir/item.txt")
            try sandbox.removeItem(at: "dir/item.txt")
            let changes = try await session.reconcileWatched()

            let (updates, deletedIds) = changes.split()
            #expect(updates == [])
            #expect(deletedIds == [fileId])
        }

        @Test func reconcileWatchedIgnoresChangesInUnwatchedFolder()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "watched", modifyDate: start)
            try sandbox.createFolder(at: "other", modifyDate: start)
            let session = try await sandbox.getSession()

            let watchedId = try await session.child(name: "watched")
            await session.watch(itemId: watchedId)

            try sandbox.createFile(at: "other/new.txt", modifyDate: end)
            try sandbox.touch("other", modifyDate: start)
            let changes = try await session.reconcileWatched()

            #expect(changes == [])
        }

        @Test func reconcileWatchedDoesNotRecurseIntoSubfolder()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir/subdir", modifyDate: start)
            let session = try await sandbox.getSession()

            let dirId = try await session.child(name: "dir")
            await session.watch(itemId: dirId)

            try sandbox.createFile(at: "dir/subdir/deep.txt", modifyDate: end)
            // Reset the subfolder's mtime so the only detectable change lives
            // one level below the watched folder.
            try sandbox.touch("dir/subdir", modifyDate: start)
            let changes = try await session.reconcileWatched()

            #expect(changes == [])
        }

        @Test func reconcileWatchedStopsAfterUnwatch() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            let dirId = try await session.child(name: "dir")
            await session.watch(itemId: dirId)
            await session.unwatch(itemId: dirId)

            try sandbox.createFile(at: "dir/new.txt", modifyDate: end)
            let changes = try await session.reconcileWatched()

            #expect(changes == [])
        }

        @Test func reconcileWatchedRespectsWatchRefCount() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            let dirId = try await session.child(name: "dir")
            await session.watch(itemId: dirId)
            await session.watch(itemId: dirId)
            await session.unwatch(itemId: dirId)

            try sandbox.createFile(at: "dir/new.txt", modifyDate: end)
            let changes = try await session.reconcileWatched()

            let (updates, _) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "new.txt")
        }

        @Test func reconcileWatchedIgnoresTrashContainer() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(
                at: ".sshadow/trash/file.txt",
                modifyDate: start
            )
            let session = try await sandbox.getSession()

            await session.watch(itemId: .trashContainer)

            try sandbox.createFile(
                at: ".sshadow/trash/new.txt",
                modifyDate: end
            )
            let changes = try await session.reconcileWatched()

            #expect(changes == [])
        }

        @Test func reconcileWatchedSurvivesVanishedWatchedFolder()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "gone", modifyDate: start)
            try sandbox.createFolder(at: "live", modifyDate: start)
            let session = try await sandbox.getSession()

            let goneId = try await session.child(name: "gone")
            let liveId = try await session.child(name: "live")
            await session.watch(itemId: goneId)
            await session.watch(itemId: liveId)

            // "gone" disappears remotely while still watched, and a change
            // lands in "live". One dead watched folder must not starve the
            // others.
            try sandbox.removeItem(at: "gone")
            try sandbox.createFile(at: "live/new.txt", modifyDate: end)

            let changes = try await session.reconcileWatched()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "new.txt")
            #expect(deletedIds == [])
        }
    }

    struct ReconcileWatchedFileTests {
        let start: Date = Date(timeIntervalSince1970: 1_750_000_000)
        let end: Date = Date(timeIntervalSince1970: 1_760_000_000)

        @Test func reconcileWatchedFileWithNoChangeReturnsEmpty()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            let fileId = try await session.child(name: "file.txt")
            await session.watch(itemId: fileId)

            let changes = try await session.reconcileWatched()

            #expect(changes == [])
        }

        @Test func reconcileWatchedFileSurfacesContentChange() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(
                at: "file.txt",
                contents: "old",
                modifyDate: start
            )
            let session = try await sandbox.getSession()

            let fileId = try await session.child(name: "file.txt")
            await session.watch(itemId: fileId)

            let updated = "updated"
            try sandbox.createFile(
                at: "file.txt",
                contents: updated,
                modifyDate: end
            )
            let changes = try await session.reconcileWatched()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.id == fileId)
            #expect(item.name == "file.txt")
            #expect(item.size == UInt64(updated.utf8.count))
            #expect(item.modifyTime == end)
            #expect(deletedIds == [])
        }

        @Test func reconcileWatchedPackageIgnoresContents() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "Doc.rtfd/TXT.rtf", modifyDate: start)
            let session = try await sandbox.getSession()

            let packageId = try await session.child(name: "Doc.rtfd")
            await session.watch(itemId: packageId)

            try sandbox.createFile(at: "Doc.rtfd/new.rtf", modifyDate: end)
            try sandbox.touch("Doc.rtfd", modifyDate: start)
            let changes = try await session.reconcileWatched()

            #expect(changes == [])
        }

        @Test func reconcileWatchedPackageSurfacesOwnChange() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "Doc.rtfd/TXT.rtf", modifyDate: start)
            let session = try await sandbox.getSession()

            let packageId = try await session.child(name: "Doc.rtfd")
            await session.watch(itemId: packageId)

            try sandbox.touch("Doc.rtfd", modifyDate: end)
            let changes = try await session.reconcileWatched()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.id == packageId)
            #expect(item.modifyTime == end)
            #expect(deletedIds == [])
        }

        @Test func reconcileWatchedFileSurfacesPermissionChange()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            let fileId = try await session.child(name: "file.txt")
            await session.watch(itemId: fileId)

            try sandbox.touch("file.txt", permissions: 0o444)
            let changes = try await session.reconcileWatched()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.id == fileId)
            #expect(item.flags == [.readable])
            #expect(deletedIds == [])
        }

        @Test func reconcileWatchedFileSurfacesDeletion() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            let fileId = try await session.child(name: "file.txt")
            await session.watch(itemId: fileId)

            try sandbox.removeItem(at: "file.txt")
            let changes = try await session.reconcileWatched()

            let (updates, deletedIds) = changes.split()
            #expect(updates == [])
            #expect(deletedIds == [fileId])
        }

        @Test func reconcileWatchedFileStopsWatchingAfterDeletion()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt", modifyDate: start)
            let session = try await sandbox.getSession()

            let fileId = try await session.child(name: "file.txt")
            await session.watch(itemId: fileId)

            try sandbox.removeItem(at: "file.txt")
            _ = try await session.reconcileWatched()

            // The vanished file was dropped from the watch set, so a second
            // pass produces no further changes and logs no errors.
            let changes = try await session.reconcileWatched()
            #expect(changes == [])
        }

        @Test func reconcileWatchedSymlinkSurfacesRetarget() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "old.txt", modifyDate: start)
            try sandbox.createFile(at: "new.txt", modifyDate: start)
            try sandbox.createSymlink(at: "link.txt", target: "old.txt")
            let session = try await sandbox.getSession()

            let linkId = try await session.id(of: "link.txt")
            await session.watch(itemId: linkId)

            try sandbox.createSymlink(at: "link.txt", target: "new.txt")
            let changes = try await session.reconcileWatched()

            let (updates, deletedIds) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "link.txt")
            #expect(item.kind == .symlink(target: "new.txt"))
            #expect(deletedIds == [linkId])
        }

        @Test func reconcileWatchedFileInvalidatesCachedContent() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(
                at: "file.txt",
                contents: "old",
                modifyDate: start
            )
            let session = try await sandbox.getSession()

            let fileId = try await session.child(name: "file.txt")
            await session.watch(itemId: fileId)

            let (warmUrl, _) = try await session.stream(
                itemId: fileId,
                range: 0..<1,
                progress: Progress()
            )
            #expect(try String(contentsOf: warmUrl, encoding: .utf8) == "old")

            try sandbox.createFile(
                at: "file.txt",
                contents: "new",
                modifyDate: end
            )
            _ = try await session.reconcileWatched()

            let (freshUrl, _) = try await session.stream(
                itemId: fileId,
                range: 0..<1,
                progress: Progress()
            )
            #expect(try String(contentsOf: freshUrl, encoding: .utf8) == "new")
        }
    }

    struct PollWatchedChangesTests {
        let start: Date = Date(timeIntervalSince1970: 1_750_000_000)
        let end: Date = Date(timeIntervalSince1970: 1_760_000_000)

        @Test func pollWatchedWithNoChangesAccumulatesEmpty() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            let dirId = try await session.child(name: "dir")
            await session.watch(itemId: dirId)

            try await session.pollWatched()

            let (_, changes) = await session.changes(since: 0)
            #expect(changes == [])
            #expect(await session.anchor == 0)
        }

        @Test func pollWatchedSurfacesChangeAndAdvancesAnchor() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir", modifyDate: start)
            let session = try await sandbox.getSession()

            let dirId = try await session.child(name: "dir")
            await session.watch(itemId: dirId)

            try sandbox.createFile(at: "dir/new.txt", modifyDate: end)
            try await session.pollWatched()

            let (_, changes) = await session.changes(since: 0)
            let (updates, _) = changes.split()
            let item = try #require(updates.only)
            #expect(item.name == "new.txt")
            #expect(await session.anchor > 0)
        }

        @Test func pollWatchedIgnoresUnwatchedFolderLeavesAnchor()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "watched", modifyDate: start)
            try sandbox.createFolder(at: "other", modifyDate: start)
            let session = try await sandbox.getSession()

            let watchedId = try await session.child(name: "watched")
            await session.watch(itemId: watchedId)

            try sandbox.createFile(at: "other/new.txt", modifyDate: end)
            try sandbox.touch("other", modifyDate: start)
            try await session.pollWatched()

            let (_, changes) = await session.changes(since: 0)
            #expect(changes == [])
            #expect(await session.anchor == 0)
        }
    }

    struct SetAttributesTests {
        @Test func setFlagsSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "perms.txt", permissions: 0o400)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "perms.txt")
            try await session.setAttributes(
                for: itemId,
                flags: .rw,
                snapshot: nil
            )

            #expect(try sandbox.permissions(of: "perms.txt") == 0o644)
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func setModifyTimeSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "modify-time.txt", contents: "test")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "modify-time.txt")
            let date = Date(timeIntervalSince1970: 1_000_000)
            try await session.setAttributes(
                for: itemId,
                modifyTime: date,
                snapshot: nil
            )

            #expect(try sandbox.modifyDate(of: "modify-time.txt") == date)
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func setAccessTimeSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "access-time.txt", contents: "test")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "access-time.txt")
            let date = Date(timeIntervalSince1970: 2_000_000)
            try await session.setAttributes(
                for: itemId,
                accessTime: date,
                snapshot: nil
            )

            #expect(try sandbox.accessDate(of: "access-time.txt") == date)
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func setAttributesForMissingFileThrows() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "missing.txt", contents: "Hello!")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "missing.txt")
            try sandbox.removeItem(at: "missing.txt")

            await #expect(throws: CoreError.itemNotFound(itemId.rawValue)) {
                try await session.setAttributes(
                    for: itemId,
                    flags: .rw,
                    snapshot: nil
                )
            }
        }

        @Test func setAttributesWhenPermissionDeniedThrows() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "locked")
            try sandbox.createFile(at: "locked/file.txt", contents: "Hello!")
            let session = try await sandbox.getSession()

            let folderId = try await session.child(name: "locked")
            let itemId = try await session.child(of: folderId, name: "file.txt")

            try sandbox.touch("locked", permissions: 0o000)
            defer { try? sandbox.touch("locked", permissions: 0o755) }

            await #expect(throws: CoreError.permissionDenied) {
                try await session.setAttributes(
                    for: itemId,
                    flags: .rw,
                    snapshot: nil
                )
            }
        }

        @Test func setAttributesWhenConnectionLostThrows() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "unreachable.txt", contents: "Hello!")

            try await confirmation("connection lost handler fires") { fired in
                let (session, ssh) = try await sandbox.makeSession(
                    connectionLostHandler: { _ in fired() }
                )
                let itemId = try await session.child(name: "unreachable.txt")

                await ssh.close()

                await #expect(throws: CoreError.serverUnreachable) {
                    try await session.setAttributes(
                        for: itemId,
                        flags: .rw,
                        snapshot: nil
                    )
                }
            }
        }
    }

    struct CreateDirectoryTests {
        @Test func createDirectoryWithPackageNameRecordsPackage()
            async throws
        {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let item = try await session.createDirectory(
                "Doc.rtfd",
                in: .rootContainer,
                snapshot: nil
            )

            #expect(item.kind == .package)
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func createDirectorySucceeds() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let item = try await session.createDirectory(
                "new-dir",
                in: .rootContainer,
                snapshot: nil
            )

            #expect(item.name == "new-dir")
            #expect(item.kind == .folder)
            #expect(item.size == nil)
            #expect(try sandbox.permissions(of: "new-dir") == 0o755)
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func createDirectoryWithIfExistsSucceedSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "existing-dir")
            let session = try await sandbox.getSession()

            let item = try await session.createDirectory(
                "existing-dir",
                in: .rootContainer,
                ifExists: .succeed,
                snapshot: nil
            )

            #expect(item.name == "existing-dir")
            #expect(item.kind == .folder)
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func reconcileFindsRemoteAdditionsInCreatedDirectory()
            async throws
        {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()
            _ = try await session.createDirectory(
                "x",
                in: .rootContainer,
                snapshot: nil
            )

            try sandbox.createFile(at: "x/child.txt", contents: "c")
            let (updates, _) = try await session.reconcileAll().split()

            #expect(updates.map(\.name) == ["child.txt"])
        }

        @Test func createDirectoryOverExistingDirectoryFindsItsChildren()
            async throws
        {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()
            try sandbox.createFile(at: "x/child.txt", contents: "c")

            _ = try await session.createDirectory(
                "x",
                in: .rootContainer,
                ifExists: .succeed,
                snapshot: nil
            )
            let (updates, _) = try await session.reconcileAll().split()

            #expect(updates.map(\.name) == ["child.txt"])
        }

        @Test func createDirectoryWithIfExistsSucceedOverFileThrows()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "existing-file")
            let session = try await sandbox.getSession()

            await #expect(throws: CoreError.filenameCollision) {
                _ = try await session.createDirectory(
                    "existing-file",
                    in: .rootContainer,
                    ifExists: .succeed,
                    snapshot: nil
                )
            }
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func createDirectoryWithIfExistsSucceedOverSymlinkThrows()
            async throws
        {
            let sandbox = TestSandbox()
            _ = try sandbox.createFolder(at: "target-dir")
            try sandbox.createSymlink(at: "link-dir", target: "target-dir")
            let session = try await sandbox.getSession()

            await #expect(throws: CoreError.filenameCollision) {
                _ = try await session.createDirectory(
                    "link-dir",
                    in: .rootContainer,
                    ifExists: .succeed,
                    snapshot: nil
                )
            }
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func createDirectoryWhenExistsThrows() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "already-exists")
            let session = try await sandbox.getSession()

            await #expect {
                try await session.createDirectory(
                    "already-exists",
                    in: .rootContainer,
                    snapshot: nil
                )
            } throws: { error in
                guard case CoreError.filenameCollision = error else {
                    return false
                }
                return true
            }
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func createDirectoryInsertsRowMatchingItemId() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let item = try await session.createDirectory(
                "row-match-dir",
                in: .rootContainer,
                snapshot: nil
            )

            let lookedUpId = try await session.child(name: "row-match-dir")
            #expect(lookedUpId == item.id)
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func createDirectoryFailureLeavesNoRow() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "collide-dir")
            let session = try await sandbox.getSession()

            await #expect(throws: CoreError.filenameCollision) {
                _ = try await session.createDirectory(
                    "collide-dir",
                    in: .rootContainer,
                    snapshot: nil
                )
            }
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }
    }

    struct CreateSymlinkTests {
        @Test func createSymlinkSucceeds() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let item = try await session.createSymlink(
                "link",
                in: .rootContainer,
                target: "/etc/hosts",
                snapshot: nil
            )

            #expect(item.name == "link")
            #expect(item.kind == .symlink(target: "/etc/hosts"))
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func createSymlinkInsertsRowMatchingItemId() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let item = try await session.createSymlink(
                "link",
                in: .rootContainer,
                target: "/dev/null",
                snapshot: nil
            )

            let lookedUpId = try await session.child(name: "link")
            #expect(lookedUpId == item.id)
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func createSymlinkFailureLeavesNoRow() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "collide")
            let session = try await sandbox.getSession()

            await #expect(throws: CoreError.filenameCollision) {
                _ = try await session.createSymlink(
                    "collide",
                    in: .rootContainer,
                    target: "/dev/null",
                    snapshot: nil
                )
            }
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }
    }

    struct MoveTests {
        @Test func moveRenamingFolderToPackageChangesKind() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "Notes/TXT.rtf", contents: "rtf")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "Notes")

            let item = try await session.move(
                itemId,
                to: .rootContainer,
                name: "Notes.rtfd",
                snapshot: nil
            )

            #expect(item.id == itemId)
            #expect(item.kind == .package)
            await #expect(throws: CoreError.itemNotFound) {
                try await session.child(of: itemId, name: "TXT.rtf")
            }
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func moveRenamingPackageToFolderChangesKind() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "Doc.rtfd/TXT.rtf", contents: "rtf")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "Doc.rtfd")

            let item = try await session.move(
                itemId,
                to: .rootContainer,
                name: "Doc",
                snapshot: nil
            )

            #expect(item.id == itemId)
            #expect(item.kind == .folder)
            let children = try await session.list(for: itemId)
            #expect(children.map(\.name) == ["TXT.rtf"])
        }

        @Test func moveRenamesFile() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "original.txt", contents: "hello")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "original.txt")

            try await session.move(
                itemId,
                to: .rootContainer,
                name: "renamed.txt",
                snapshot: nil
            )

            let newId = try await session.child(name: "renamed.txt")
            #expect(itemId == newId)
            #expect(sandbox.exists(at: "renamed.txt"))
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func moveToNewParent() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt", contents: "hello")
            try sandbox.createFolder(at: "dest")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "file.txt")
            let destId = try await session.child(name: "dest")

            try await session.move(
                itemId,
                to: destId,
                name: "file.txt",
                snapshot: nil
            )

            let movedId = try await session.child(of: destId, name: "file.txt")
            #expect(itemId == movedId)
            #expect(sandbox.exists(at: "dest/file.txt"))
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func moveToNewParentAndRename() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "old.txt", contents: "hello")
            try sandbox.createFolder(at: "dest")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "old.txt")
            let destId = try await session.child(name: "dest")

            try await session.move(
                itemId,
                to: destId,
                name: "new.txt",
                snapshot: nil
            )

            let parent = try await session.parent(of: itemId)
            #expect(parent == destId)

            let name = try await session.name(of: itemId)
            #expect(name == "new.txt")
            let changes = try await session.reconcileAll()
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
                to: .trashContainer,
                name: "file.txt",
                snapshot: nil
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
            try await session.removeFile(for: itemId, snapshot: nil)

            #expect(!sandbox.exists(at: "delete.txt"))
            let changes = try await session.reconcileAll()
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
            try await session.removeFile(for: itemId, snapshot: nil)

            #expect(!sandbox.exists(at: "folder/delete.txt"))
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func removeFileMissingThrows() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "missing.txt")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "missing.txt")
            try await session.removeFile(for: itemId, snapshot: nil)

            await #expect(throws: CoreError.itemNotFound(itemId)) {
                try await session.removeFile(for: itemId, snapshot: nil)
            }
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }
    }

    struct RemoveDirectoryTests {
        @Test func removeDirectorySucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "delete")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "delete")
            try await session.removeDirectory(for: itemId, snapshot: nil)

            #expect(!sandbox.exists(at: "delete"))
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func removeDirectoryWithContentsSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "non-empty/child.txt")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "non-empty")
            try await session.removeDirectory(for: itemId, snapshot: nil)

            #expect(!sandbox.exists(at: "non-empty"))
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }
    }

    struct IgnoredItemTests {
        @Test func removingIgnoredFileKeepsRemoteCopy() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "b.txt", contents: "b")
            let session = try await sandbox.getSession()
            let bId = try await session.child(name: "b.txt")

            try await session.removeFile(
                for: bId,
                snapshot: [folder("", text("b.txt\n"))]
            )

            #expect(sandbox.exists(at: "b.txt"))
            await #expect(throws: CoreError.itemNotFound(bId.rawValue)) {
                try await session.item(for: bId)
            }
        }

        @Test func uploadToIgnoredNameIsSkipped() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "a.log", in: .group, contents: "a")
            let session = try await sandbox.getSession()

            await #expect(throws: CoreError.ignored) {
                try await session.upload(
                    "a.log",
                    to: .rootContainer,
                    file: sandbox.url(for: "a.log", in: .group),
                    snapshot: [folder("", text("*.log\n"))],
                    progress: Progress()
                )
            }

            #expect(!sandbox.exists(at: "a.log"))
        }

        @Test func trashingIgnoredItemIsSkipped() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "b.txt", contents: "b")
            let session = try await sandbox.getSession()
            let bId = try await session.child(name: "b.txt")

            await #expect(throws: CoreError.ignored) {
                try await session.move(
                    bId,
                    to: .trashContainer,
                    name: "b.txt",
                    snapshot: [folder("", text("b.txt\n"))]
                )
            }

            #expect(sandbox.exists(at: "b.txt"))
        }

        @Test func changedRulesCallHandler() async throws {
            let sandbox = TestSandbox()
            let files = [folder("", text("build/\n"))]

            try await confirmation { called in
                let session = try await sandbox.getSession(
                    ignoreRulesChangedHandler: { called() }
                )
                for _ in 0..<2 {
                    await #expect(throws: CoreError.ignored) {
                        try await session.createDirectory(
                            "build",
                            in: .rootContainer,
                            snapshot: files
                        )
                    }
                }
            }
        }

        @Test func matchingNameIsIgnored() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            await #expect(throws: CoreError.ignored) {
                try await session.createDirectory(
                    "build",
                    in: .rootContainer,
                    snapshot: [folder("", text("build/\n"))]
                )
            }

            #expect(!sandbox.exists(at: "build"))
        }

        @Test func otherNameIsNotIgnored() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            _ = try await session.createSymlink(
                "build",
                in: .rootContainer,
                target: "/dev/null",
                snapshot: [folder("", text("build/\n"))]
            )

            #expect(sandbox.exists(at: "build"))
        }

        @Test func nestedRulesOverrideParentRules() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "src")
            let session = try await sandbox.getSession()
            let srcId = try await session.child(name: "src")
            let files = [
                folder("", text("*.log\n")),
                folder("src", text("!keep.log\n")),
            ]

            _ = try await session.createSymlink(
                "keep.log",
                in: srcId,
                target: "/dev/null",
                snapshot: files
            )
            await #expect(throws: CoreError.ignored) {
                try await session.createSymlink(
                    "other.log",
                    in: srcId,
                    target: "/dev/null",
                    snapshot: files
                )
            }

            #expect(sandbox.exists(at: "src/keep.log"))
            #expect(!sandbox.exists(at: "src/other.log"))
        }

        @Test func remoteIgnoreFileIsReadFromServer() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "src/.sshadowignore", contents: "*.o\n")
            let session = try await sandbox.getSession()
            let srcId = try await session.child(name: "src")

            await #expect(throws: CoreError.ignored) {
                try await session.createSymlink(
                    "out.o",
                    in: srcId,
                    target: "/dev/null",
                    snapshot: [folder(""), folder("src", unresolved())]
                )
            }

            #expect(!sandbox.exists(at: "src/out.o"))
        }

        @Test func missingRemoteIgnoreFileHasNoRules() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            _ = try await session.createSymlink(
                "out.o",
                in: .rootContainer,
                target: "/dev/null",
                snapshot: [folder("", unresolved())]
            )

            #expect(sandbox.exists(at: "out.o"))
        }

        @Test func onlyConfiguredFilenamesApply() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            _ = try await session.createDirectory(
                "build",
                in: .rootContainer,
                snapshot: [folder("", text("build/\n", named: ".gitignore"))]
            )

            #expect(sandbox.exists(at: "build"))
        }

        @Test func mismatchedDirectoriesAreNotIgnored() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "src")
            let session = try await sandbox.getSession()
            let srcId = try await session.child(name: "src")

            _ = try await session.createDirectory(
                "build",
                in: srcId,
                snapshot: [folder(""), folder("lib", text("build/\n"))]
            )

            #expect(sandbox.exists(at: "src/build"))
        }
    }

    struct UploadTests {
        @Test func uploadPackageRecordsPackageKind() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(
                at: "src.rtfd/TXT.rtf",
                in: .group,
                contents: "rtf"
            )
            let source = sandbox.url(for: "src.rtfd", in: .group)
            let session = try await sandbox.getSession()

            let item = try await session.upload(
                "Doc.rtfd",
                to: .rootContainer,
                file: source,
                snapshot: nil,
                progress: Progress()
            )

            #expect(item.kind == .package)
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func uploadSmallFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            let data = "Hello, World!\n"
            try data.write(to: uploadUrl, atomically: false, encoding: .utf8)

            let filename = "small-file.txt"
            let url = sandbox.url(for: filename)
            let session = try await sandbox.getSession()

            let progress = Progress()
            let item = try await session.upload(
                filename,
                to: .rootContainer,
                file: uploadUrl,
                snapshot: nil,
                progress: progress
            )
            let currId = try await session.child(name: filename)

            #expect(item.name == filename)
            #expect(item.size == UInt64(data.utf8.count))
            #expect(FileManager.default.fileExists(at: url))
            #expect(try String(contentsOf: url, encoding: .utf8) == data)
            #expect(progress.isFinished)
            #expect(try sandbox.permissions(of: filename) == 0o644)
            #expect(currId == item.id)
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func uploadLargeFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            let data = Data(count: 10_485_760)
            try data.write(to: uploadUrl)

            let filename = "large-file.txt"
            let url = sandbox.url(for: filename)
            let session = try await sandbox.getSession()

            let progress = Progress()
            let item = try await session.upload(
                filename,
                to: .rootContainer,
                file: uploadUrl,
                snapshot: nil,
                progress: progress
            )
            let currId = try await session.child(name: filename)

            #expect(item.name == filename)
            #expect(item.size == UInt64(data.count))
            #expect(FileManager.default.fileExists(at: url))
            #expect(try Data(contentsOf: url) == data)
            #expect(progress.isFinished)
            #expect(try sandbox.permissions(of: filename) == 0o644)
            #expect(currId == item.id)
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func uploadFailureLeavesNoRow() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "collide-upload")
            let session = try await sandbox.getSession()

            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            try Data("data".utf8).write(to: uploadUrl)

            await #expect(throws: CoreError.cannotSynchronize) {
                _ = try await session.upload(
                    "collide-upload",
                    to: .rootContainer,
                    file: uploadUrl,
                    snapshot: nil,
                    progress: Progress()
                )
            }
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func uploadCancelledThrowsUserCancelled() async throws {
            let sandbox = TestSandbox()
            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            let data = Data(count: 10_485_760)
            try data.write(to: uploadUrl)

            let session = try await sandbox.getSession()

            let progress = Progress()
            progress.cancel()

            await #expect(throws: CoreError.userCancelled) {
                _ = try await session.upload(
                    "cancelled.dat",
                    to: .rootContainer,
                    file: uploadUrl,
                    snapshot: nil,
                    progress: progress
                )
            }
        }

        @Test func uploadCancelledMidwayRemovesPartialFile() async throws {
            let sandbox = TestSandbox()
            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            try Data(count: 256 << 20).write(to: uploadUrl)
            let session = try await sandbox.getSession()

            let progress = Progress()
            let cancellation = cancelOnFirstBytes(progress)
            defer { cancellation.invalidate() }

            await #expect(throws: CoreError.userCancelled) {
                _ = try await session.upload(
                    "partial.dat",
                    to: .rootContainer,
                    file: uploadUrl,
                    snapshot: nil,
                    progress: progress
                )
            }
            #expect(
                !FileManager.default.fileExists(
                    at: sandbox.url(for: "partial.dat")
                )
            )
            #expect(try sandbox.stagedUploads() == [])
        }

        @Test func closeDuringUploadLeavesNoPartialFile() async throws {
            let sandbox = TestSandbox()
            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            try Data(count: 256 << 20).write(to: uploadUrl)
            let session = try await sandbox.getSession()

            let progress = Progress()
            let upload = Task {
                try await session.upload(
                    "partial.dat",
                    to: .rootContainer,
                    file: uploadUrl,
                    chunkSize: Self.slowChunkSize,
                    snapshot: nil,
                    progress: progress
                )
            }
            try await waitForBytes(progress)
            await session.close()

            await #expect(throws: CoreError.serverUnreachable) {
                _ = try await upload.value
            }
            #expect(
                !FileManager.default.fileExists(
                    at: sandbox.url(for: "partial.dat")
                )
            )
        }

        @Test func uploadCancelledBeforeWritingKeepsExistingFile()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "existing.txt", contents: "original")
            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            try Data("replacement".utf8).write(to: uploadUrl)
            let session = try await sandbox.getSession()

            let progress = Progress()
            progress.cancel()

            await #expect(throws: CoreError.userCancelled) {
                _ = try await session.upload(
                    "existing.txt",
                    to: .rootContainer,
                    file: uploadUrl,
                    snapshot: nil,
                    progress: progress
                )
            }
            let url = sandbox.url(for: "existing.txt")
            #expect(try String(contentsOf: url, encoding: .utf8) == "original")
        }

        @Test func uploadCancelledMidwayKeepsExistingFile() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "existing.dat", contents: "original")
            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            try Data(count: 256 << 20).write(to: uploadUrl)
            let session = try await sandbox.getSession()

            let progress = Progress()
            let cancellation = cancelOnFirstBytes(progress)
            defer { cancellation.invalidate() }

            await #expect(throws: CoreError.userCancelled) {
                _ = try await session.upload(
                    "existing.dat",
                    to: .rootContainer,
                    file: uploadUrl,
                    snapshot: nil,
                    progress: progress
                )
            }
            #expect(try sandbox.contents(of: "existing.dat") == "original")
            #expect(try sandbox.stagedUploads() == [])
        }

        @Test func closeDuringUploadKeepsExistingFile() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "existing.dat", contents: "original")
            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            try Data(count: 256 << 20).write(to: uploadUrl)
            let session = try await sandbox.getSession()

            let progress = Progress()
            let upload = Task {
                try await session.upload(
                    "existing.dat",
                    to: .rootContainer,
                    file: uploadUrl,
                    chunkSize: Self.slowChunkSize,
                    snapshot: nil,
                    progress: progress
                )
            }
            try await waitForBytes(progress)
            await session.close()

            await #expect(throws: CoreError.serverUnreachable) {
                _ = try await upload.value
            }
            #expect(try sandbox.contents(of: "existing.dat") == "original")
        }

        @Test func uploadPackageCancelledMidwayKeepsExistingPackage()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createPackage(
                at: "Doc.rtfd",
                files: [.file(path: "text.rtf", contents: "old")]
            )
            let source = try sandbox.createPackage(
                at: "src.rtfd",
                in: .group,
                files: [.file(path: "text.rtf", contents: "new")]
            )
            try Data(count: 256 << 20).write(
                to: source.appending(path: "big.dat")
            )
            let session = try await sandbox.getSession()

            let progress = Progress()
            let cancellation = cancelOnFirstBytes(progress)
            defer { cancellation.invalidate() }

            await #expect(throws: CoreError.userCancelled) {
                _ = try await session.upload(
                    "Doc.rtfd",
                    to: .rootContainer,
                    file: source,
                    snapshot: nil,
                    progress: progress
                )
            }
            #expect(try sandbox.contents(of: "Doc.rtfd/text.rtf") == "old")
            #expect(!sandbox.exists(at: "Doc.rtfd/big.dat"))
            #expect(try sandbox.stagedUploads() == [])
        }

        @Test func uploadOverExistingFileLeavesNoStagedUploads()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "existing.txt", contents: "original")
            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            try Data("replacement".utf8).write(to: uploadUrl)
            let session = try await sandbox.getSession()
            let itemId = try await session.child(name: "existing.txt")

            let item = try await session.upload(
                "existing.txt",
                to: .rootContainer,
                file: uploadUrl,
                snapshot: nil,
                progress: Progress()
            )

            #expect(item.id == itemId)
            #expect(try sandbox.contents(of: "existing.txt") == "replacement")
            #expect(try sandbox.stagedUploads() == [])
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func uploadIntoLockedFolderThrowsCannotSynchronize()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(
                at: "locked/existing.txt",
                contents: "original",
                permissions: 0o666
            )
            try sandbox.touch("locked", permissions: 0o555)
            defer { try? sandbox.touch("locked", permissions: 0o755) }
            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            try Data("replacement".utf8).write(to: uploadUrl)
            let session = try await sandbox.getSession()
            let lockedId = try await session.child(name: "locked")

            await #expect(throws: CoreError.cannotSynchronize) {
                _ = try await session.upload(
                    "existing.txt",
                    to: lockedId,
                    file: uploadUrl,
                    snapshot: nil,
                    progress: Progress()
                )
            }
            #expect(
                try sandbox.contents(of: "locked/existing.txt") == "original"
            )
            #expect(try sandbox.stagedUploads() == [])
        }

        @Test func uploadRecreatesDeletedUploadsFolder() async throws {
            let sandbox = TestSandbox()
            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            try Data("contents".utf8).write(to: uploadUrl)
            let session = try await sandbox.getSession()

            _ = try await session.upload(
                "first.txt",
                to: .rootContainer,
                file: uploadUrl,
                snapshot: nil,
                progress: Progress()
            )
            _ = try sandbox.removeItem(at: ".sshadow")
            _ = try await session.upload(
                "second.txt",
                to: .rootContainer,
                file: uploadUrl,
                snapshot: nil,
                progress: Progress()
            )

            #expect(try sandbox.contents(of: "second.txt") == "contents")
            #expect(try sandbox.stagedUploads() == [])
        }

        @Test func uploadWithoutUploadsFolderThrowsCannotSynchronize()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: ".sshadow", contents: "not a folder")
            try sandbox.createFile(at: "existing.txt", contents: "original")
            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            try Data("replacement".utf8).write(to: uploadUrl)
            let session = try await sandbox.getSession()

            await #expect(throws: CoreError.cannotSynchronize) {
                _ = try await session.upload(
                    "existing.txt",
                    to: .rootContainer,
                    file: uploadUrl,
                    snapshot: nil,
                    progress: Progress()
                )
            }
            #expect(try sandbox.contents(of: "existing.txt") == "original")
        }

        @Test func removeStaleUploadsKeepsRecentOnes() async throws {
            let sandbox = TestSandbox()
            let old = Date.now.addingTimeInterval(-2 * 24 * 60 * 60)
            try sandbox.createFile(
                at: ".sshadow/uploads/old-file",
                modifyDate: old
            )
            try sandbox.createFile(
                at: ".sshadow/uploads/old-package/text.rtf",
                modifyDate: old
            )
            try sandbox.touch(".sshadow/uploads/old-package", modifyDate: old)
            try sandbox.createFile(at: ".sshadow/uploads/recent-file")
            let session = try await sandbox.getSession()

            await session.removeStaleUploads()

            #expect(try sandbox.stagedUploads() == ["recent-file"])
        }

        @Test func removeStaleUploadsWithoutUploadsFolderSucceeds()
            async throws
        {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            await session.removeStaleUploads()

            #expect(try sandbox.stagedUploads() == [])
        }

        private static let slowChunkSize: UInt64 = 1024

        private func waitForBytes(_ progress: Progress) async throws {
            while progress.completedUnitCount == 0 {
                try await Task.sleep(for: .milliseconds(1))
            }
        }

        private func cancelOnFirstBytes(
            _ progress: Progress
        ) -> NSKeyValueObservation {
            progress.observe(\.completedUnitCount) { progress, _ in
                if progress.completedUnitCount > 0 { progress.cancel() }
            }
        }

        @Test func uploadEmptyFileToFolderSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "folder")
            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            try Data().write(to: uploadUrl)

            let url = sandbox.url(for: "folder/file.txt")
            let session = try await sandbox.getSession()

            let progress = Progress()
            let folderId = try await session.child(name: "folder")
            let item = try await session.upload(
                "file.txt",
                to: folderId,
                file: uploadUrl,
                snapshot: nil,
                progress: progress
            )
            let currId = try await session.child(of: folderId, name: "file.txt")

            #expect(item.name == "file.txt")
            #expect(item.size == 0)
            #expect(FileManager.default.fileExists(at: url))
            #expect(try Data(contentsOf: url).isEmpty)
            #expect(progress.isFinished)
            #expect(try sandbox.permissions(of: "folder/file.txt") == 0o644)
            #expect(currId == item.id)
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func uploadPackageReproducesTree() async throws {
            let sandbox = TestSandbox()
            let source = try sandbox.createPackage(
                at: "Source.rtfd",
                in: .group,
                files: [
                    .file(path: "TXT.rtf", contents: "{\rtf1 hello}"),
                    .file(path: "image.png", contents: "png"),
                    .link(path: "link.rtf", target: "TXT.rtf"),
                    .link(path: "broken", target: "missing"),
                ]
            )
            let dest = sandbox.url(for: "Doc.rtfd")
            let session = try await sandbox.getSession()

            let progress = Progress()
            let item = try await session.upload(
                "Doc.rtfd",
                to: .rootContainer,
                file: source,
                snapshot: nil,
                progress: progress
            )

            #expect(item.name == "Doc.rtfd")
            #expect(item.kind == .package)
            #expect(try await session.child(name: "Doc.rtfd") == item.id)
            #expect(try Manifest(from: dest) == Manifest(from: source))
            #expect(try contents(of: dest) == contents(of: source))
            #expect(try sandbox.target(of: "Doc.rtfd/link.rtf") == "TXT.rtf")
            let totalSize = try Manifest(from: source).totalSize()
            #expect(progress.totalUnitCount == Int64(totalSize))
            #expect(progress.isFinished)
            let changes = try await session.reconcileAll()
            #expect(changes == [])
        }

        @Test func uploadEmptyPackageSucceeds() async throws {
            let sandbox = TestSandbox()
            let source = try sandbox.createPackage(
                at: "Source.rtfd",
                in: .group,
                files: []
            )
            let session = try await sandbox.getSession()

            let progress = Progress()
            let item = try await session.upload(
                "Empty.rtfd",
                to: .rootContainer,
                file: source,
                snapshot: nil,
                progress: progress
            )

            #expect(item.kind == .package)
            #expect(try sandbox.permissions(of: "Empty.rtfd") == 0o755)
            #expect(
                try Manifest(from: sandbox.url(for: "Empty.rtfd")).entries
                    .count == 1
            )
            #expect(progress.isFinished)
        }

        @Test func uploadPackageWithLockedFolderThrowsCannotSynchronize()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFile(
                at: "Doc.rtfd/Locked/inside.txt",
                in: .group,
                contents: "locked"
            )
            try sandbox.touch("Doc.rtfd/Locked", in: .group, permissions: 0o555)
            defer {
                try? sandbox.touch(
                    "Doc.rtfd/Locked",
                    in: .group,
                    permissions: 0o755
                )
            }
            let source = sandbox.url(for: "Doc.rtfd", in: .group)
            let session = try await sandbox.getSession()

            await #expect(throws: CoreError.cannotSynchronize) {
                _ = try await session.upload(
                    "Bundle.app",
                    to: .rootContainer,
                    file: source,
                    snapshot: nil,
                    progress: Progress()
                )
            }
            #expect(!sandbox.exists(at: "Bundle.app"))
        }

        @Test func uploadPackageCancelledThrowsUserCancelled() async throws {
            let sandbox = TestSandbox()
            let source = try sandbox.createPackage(at: "Doc.rtfd", in: .group)
            let session = try await sandbox.getSession()

            let progress = Progress()
            progress.cancel()

            await #expect(throws: CoreError.userCancelled) {
                _ = try await session.upload(
                    "Bundle.app",
                    to: .rootContainer,
                    file: source,
                    snapshot: nil,
                    progress: progress
                )
            }
        }

        @Test func uploadPackageOverExistingReplacesContents() async throws {
            let sandbox = TestSandbox()

            let dest = try sandbox.createPackage(
                at: "Doc.rtfd",
                files: [
                    .file(path: "text.rtf", contents: "old"),
                    .file(path: "stale.png", contents: "png"),
                ]
            )

            let source = try sandbox.createPackage(
                at: "src.rtfd",
                in: .group,
                files: [
                    .file(path: "text.rtf", contents: "new"),
                    .file(path: "fresh.jpg", contents: "jpg"),
                ]
            )

            let session = try await sandbox.getSession()
            let itemId = try await session.child(name: "Doc.rtfd")

            let progress = Progress()
            let item = try await session.upload(
                "Doc.rtfd",
                to: .rootContainer,
                file: source,
                snapshot: nil,
                progress: progress
            )

            #expect(item.id == itemId)
            #expect(item.kind == .package)
            #expect(try contents(of: dest) == contents(of: source))
            #expect(!sandbox.exists(at: "Doc.rtfd/stale.png"))
            #expect(progress.isFinished)
            let changes = try await session.reconcileAll()
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

            await #expect(throws: CoreError.userCancelled) {
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

        @Test func downloadMissingFileThrowsNoSuchItem() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "missing.txt", contents: "Hello!")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "missing.txt")
            try sandbox.removeItem(at: "missing.txt")

            await #expect(throws: CoreError.itemNotFound(itemId.rawValue)) {
                _ = try await session.download(
                    itemId: itemId,
                    progress: Progress()
                )
            }
        }

        @Test func downloadPackageReproducesTree() async throws {
            let sandbox = TestSandbox()
            let source = try sandbox.createPackage(at: "Doc.rtfd")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "Doc.rtfd")
            let progress = Progress()
            let (url, item) = try await session.download(
                itemId: itemId,
                progress: progress
            )

            #expect(item.id == itemId)
            #expect(item.kind == .package)
            #expect(
                url == sandbox.url(for: itemId.rawValue, in: .group)
            )
            #expect(try Manifest(from: url) == Manifest(from: source))
            #expect(try contents(of: url) == contents(of: source))
            let totalSize = try Manifest(from: source).totalSize()
            #expect(progress.totalUnitCount == Int64(totalSize))
            #expect(progress.isFinished)
        }

        @Test func downloadEmptyPackageSucceeds() async throws {
            let sandbox = TestSandbox()
            let source = try sandbox.createFolder(
                at: "Doc.rtfd",
                permissions: 0o700
            )
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "Doc.rtfd")
            let progress = Progress()
            let (url, _) = try await session.download(
                itemId: itemId,
                progress: progress
            )

            #expect(try Manifest(from: url) == Manifest(from: source))
            #expect(progress.isFinished)
        }

        @Test func downloadPackageWithLockedFolderThrowsCannotSynchronize()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createPackage(
                at: "Doc.rtfd",
                files: [.file(path: "Locked/inside.txt", contents: "locked")]
            )
            try sandbox.touch("Doc.rtfd/Locked", permissions: 0o555)
            defer {
                try? sandbox.touch("Doc.rtfd/Locked", permissions: 0o755)
            }
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "Doc.rtfd")
            await #expect(throws: CoreError.cannotSynchronize) {
                _ = try await session.download(
                    itemId: itemId,
                    progress: Progress()
                )
            }
            #expect(
                !FileManager.default.fileExists(
                    at: sandbox.url(for: itemId.rawValue, in: .group)
                )
            )
        }

        @Test func downloadPackageReplacesPreviousDownload() async throws {
            let sandbox = TestSandbox()
            let source = try sandbox.createPackage(at: "Doc.rtfd")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "Doc.rtfd")
            _ = try await session.download(itemId: itemId, progress: Progress())
            try sandbox.removeItem(at: "Doc.rtfd/image.png")
            let (url, _) = try await session.download(
                itemId: itemId,
                progress: Progress()
            )

            #expect(try Manifest(from: url) == Manifest(from: source))
            #expect(try contents(of: url) == contents(of: source))
        }

        @Test func downloadMissingPackageThrowsNoSuchItem() async throws {
            let sandbox = TestSandbox()
            try sandbox.createPackage(at: "Missing.rtfd")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "Missing.rtfd")
            try sandbox.removeItem(at: "Missing.rtfd")

            await #expect(throws: CoreError.itemNotFound(itemId.rawValue)) {
                _ = try await session.download(
                    itemId: itemId,
                    progress: Progress()
                )
            }
        }

        @Test func downloadPackageCancelledThrowsUserCancelled() async throws {
            let sandbox = TestSandbox()
            try sandbox.createPackage(at: "Doc.rtfd")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "Doc.rtfd")
            let progress = Progress()
            progress.cancel()

            await #expect(throws: CoreError.userCancelled) {
                _ = try await session.download(
                    itemId: itemId,
                    progress: progress
                )
            }
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

        @Test func streamAfterUploadReturnsUploadedContents() async throws {
            let sandbox = TestSandbox()
            let old = Data(repeating: 0xAA, count: Int(chunkSize) * 2)
            let new = Data(repeating: 0xBB, count: Int(chunkSize) * 2)
            try sandbox.createFile(at: "edited.dat", data: old)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "edited.dat")
            let (warmUrl, _) = try await session.stream(
                itemId: itemId,
                range: 0..<1,
                progress: Progress()
            )
            #expect(try Data(contentsOf: warmUrl).prefix(1) == old.prefix(1))

            let uploadUrl = sandbox.url(for: UUID().uuidString, in: .group)
            try new.write(to: uploadUrl)
            let item = try await session.upload(
                "edited.dat",
                to: .rootContainer,
                file: uploadUrl,
                snapshot: nil,
                progress: Progress()
            )
            #expect(item.id == itemId)

            let (freshUrl, _) = try await session.stream(
                itemId: itemId,
                range: 0..<(chunkSize * 2),
                progress: Progress()
            )
            #expect(try Data(contentsOf: freshUrl) == new)
        }

        @Test func streamAfterDownloadOfReadOnlyFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let data = Data(repeating: 0xAB, count: Int(chunkSize))
            try sandbox.createFile(
                at: "readonly.dat",
                data: data,
                permissions: 0o444
            )
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "readonly.dat")
            _ = try await session.download(itemId: itemId, progress: Progress())
            let (url, _) = try await session.stream(
                itemId: itemId,
                range: 0..<1,
                progress: Progress()
            )

            #expect(try Data(contentsOf: url) == data)
        }

        @Test func streamCancelledThrowsUserCancelled() async throws {
            let sandbox = TestSandbox()
            let data = Data(repeating: 0xAB, count: Int(chunkSize))
            try sandbox.createFile(at: "cancel.dat", data: data)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(name: "cancel.dat")
            let progress = Progress()
            progress.cancel()

            await #expect(throws: CoreError.userCancelled) {
                _ = try await session.stream(
                    itemId: itemId,
                    range: 0..<1,
                    progress: progress
                )
            }
        }
    }

    struct PollTurnTakingTests {
        @Test func reconcileAllThrowsWhenItsTaskIsCancelled() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "dir/file.txt")
            let session = try await sandbox.getSession()

            let task = Task { try await session.reconcileAll() }
            task.cancel()

            await #expect(throws: CancellationError.self) {
                _ = try await task.value
            }
        }

        @Test func reconcileWatchedThrowsWhenItsTaskIsCancelled()
            async throws
        {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir")
            let session = try await sandbox.getSession()

            let dirId = try await session.child(name: "dir")
            await session.watch(itemId: dirId)

            let task = Task { try await session.reconcileWatched() }
            task.cancel()

            await #expect(throws: CancellationError.self) {
                _ = try await task.value
            }
        }

        @Test func operationWaitsForRunningPoll() async throws {
            let sandbox = TestSandbox()
            // A tree large enough that reconcileAll is still walking the
            // server when the operation arrives.
            for i in 0..<60 {
                try sandbox.createFile(at: "dir/file\(i).txt")
            }
            let session = try await sandbox.getSession()
            // A change the poll should surface.
            try sandbox.createFile(at: "new.txt")

            let poll = Task { try await session.pollAll() }
            // Wait until the poll's reconcile is actually in flight.
            while await session.reconcileTask == nil {
                await Task.yield()
            }

            _ = try await session.createDirectory(
                "newdir",
                in: .rootContainer,
                snapshot: nil
            )

            // The poll finishes and emits its changes.
            try await poll.value
            #expect(await session.anchor > 0)
        }

        @Test func pollWaitsForOutstandingOperation() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt")
            let latch = Latch()
            let (session, ssh) = try await sandbox.makeSession(
                connectionLostHandler: { _ in await latch.wait() }
            )
            let itemId = try await session.child(name: "file.txt")
            await ssh.close()

            // The operation stays outstanding until the latch opens.
            let operation = Task {
                try await session.setAttributes(
                    for: itemId,
                    flags: .rw,
                    snapshot: nil
                )
            }
            try await waitUntilOutstanding(session)

            let poll = Task { try await session.pollAll() }
            for _ in 0..<100 {
                await Task.yield()
            }
            #expect(await session.reconcileTask == nil)

            await latch.open()
            await #expect(throws: CoreError.serverUnreachable) {
                try await operation.value
            }
            await #expect(throws: CoreError.serverUnreachable) {
                try await poll.value
            }
        }

        @Test func operationTracksAndReleasesOutstandingCount() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt")
            let latch = Latch()
            let (session, ssh) = try await sandbox.makeSession(
                connectionLostHandler: { _ in await latch.wait() }
            )
            let itemId = try await session.child(name: "file.txt")
            await ssh.close()

            #expect(await session.outstanding == 0)

            let operation = Task {
                try await session.setAttributes(
                    for: itemId,
                    flags: .rw,
                    snapshot: nil
                )
            }
            try await waitUntilOutstanding(session)
            #expect(await session.outstanding == 1)

            await latch.open()
            _ = try? await operation.value
            #expect(await session.outstanding == 0)
        }
    }

    struct TickGatingTests {
        @Test func tickPollsWhenIdleAndUnblocked() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(at: "dir")
            let session = try await sandbox.getSession(idleTimeProvider: {
                .zero
            })

            // A change a due poll should surface.
            try sandbox.createFile(at: "dir/new.txt")

            // A zero interval plus zero idle makes pollAll due immediately.
            await session.start(pollInterval: .zero)
            await session.stop()  // stop the loop; the schedule remains

            try await session.tick()

            #expect(await session.anchor > 0)
        }

        @Test func tickSkipsPollWhileOperationOutstanding() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(at: "file.txt")
            let latch = Latch()
            let (session, ssh) = try await sandbox.makeSession(
                idleTimeProvider: { .zero },
                connectionLostHandler: { _ in await latch.wait() }
            )
            let itemId = try await session.child(name: "file.txt")

            await session.start(pollInterval: .zero)
            await session.stop()
            await ssh.close()

            let operation = Task {
                try await session.setAttributes(
                    for: itemId,
                    flags: .rw,
                    snapshot: nil
                )
            }
            try await waitUntilOutstanding(session)

            // The poll is due, but must be skipped while the operation runs.
            try await session.tick()
            #expect(await session.reconcileTask == nil)

            await latch.open()
            _ = try? await operation.value
        }
    }
}
