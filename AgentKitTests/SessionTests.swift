import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH
import Testing

@testable import AgentKit

extension TestSandbox {
    fileprivate func getSession() async throws -> Session {
        let config = try getConnectionConfig()
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
            sharedUrl: shared
        )

        var folders: [NSFileProviderItemIdentifier] = [.rootContainer]
        while !folders.isEmpty {
            let folder = folders.removeFirst()
            let items = try await session.list(for: folder)
            for item in items {
                if item.kind == .folder, (item.permissions ?? 0) & 0o400 != 0 {
                    folders.append(item.id)
                }
            }
        }

        return session
    }
}

struct SessionTests {
    struct NameChildParentPathTests {
        @Test func filePropertyReturnsFilenameForSimpleItem() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "file.txt")
            let session = try await sandbox.getSession()

            let simpleFile = try await session.child(path: "file.txt")
            let name = try await session.name(of: simpleFile)
            #expect(name == "file.txt")
        }

        @Test func filePropertyReturnsFilenameForNestedItem() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "folder/file.txt")
            let session = try await sandbox.getSession()

            let nestedFile = try await session.child(path: "folder/file.txt")
            let name = try await session.name(of: nestedFile)
            #expect(name == "file.txt")
        }

        @Test func parentOfRootContainerIsRootContainer() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let parent = try await session.parent(of: .rootContainer)
            #expect(parent == .rootContainer)
        }

        @Test func parentOfTopLevelItemIsRootContainer() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(path: "folder")
            let session = try await sandbox.getSession()

            let topLevel = try await session.child(path: "folder")
            let parent = try await session.parent(of: topLevel)
            #expect(parent == .rootContainer)
        }

        @Test func parentOfTrashContainerIsSSHadowFolder() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let parent = try await session.parent(of: .trashContainer)
            #expect(parent == .sshadowContainer)
        }

        @Test func parentOfItemInTrashIsTrashContainer() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: ".sshadow/trash/file.txt")
            let session = try await sandbox.getSession()

            let itemInTrashes = try await session.child(
                path: ".sshadow/trash/file.txt"
            )
            let parent = try await session.parent(of: itemInTrashes)
            #expect(parent == .trashContainer)
        }

        @Test func parentOfNestedItemIsParentFolder() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "folder/file.txt")
            let session = try await sandbox.getSession()

            let nested = try await session.child(path: "folder/file.txt")
            let actual = try await session.parent(of: nested)
            let expected = try await session.child(path: "folder")
            #expect(actual == expected)
        }

        @Test func parentOfDeeplyNestedItemIsImmediateParent() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "folder/subfolder/file.txt")
            let session = try await sandbox.getSession()

            let deeplyNested = try await session.child(
                path: "folder/subfolder/file.txt"
            )
            let actual = try await session.parent(of: deeplyNested)
            let expected = try await session.child(path: "folder/subfolder")
            #expect(actual == expected)
        }

        @Test func trashFolderIsIsTrashContainer() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let childOfRoot = try await session.child(path: ".sshadow/trash")
            #expect(childOfRoot == .trashContainer)
        }

        @Test func childOfTrashContainerReturnsItemInTrashes() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: ".sshadow/trash/file.txt")
            let session = try await sandbox.getSession()

            let actual = try await session.child(
                of: .trashContainer,
                path: "file.txt"
            )
            let expected = try await session.child(
                path: ".sshadow/trash/file.txt"
            )
            #expect(actual == expected)
        }

        @Test func childOfItemReturnsNestedItem() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "folder/file.txt")
            let session = try await sandbox.getSession()

            let parent = try await session.child(path: "folder")
            let actual = try await session.child(of: parent, path: "file.txt")
            let expected = try await session.child(path: "folder/file.txt")
            #expect(actual == expected)
        }

        @Test func pathForRootContainerReturnsConfigPath() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let path = await session.path(for: .rootContainer)
            #expect(path == sandbox.mount.path())
        }

        @Test func pathForItemReturnsCombinedPath() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "folder/file.txt")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "folder/file.txt")
            let path = await session.path(for: itemId)
            #expect(path == "\(sandbox.mount.path())/folder/file.txt")
        }

        @Test func pathForNameInParentReturnsCombinedPath() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "folder/file.txt")
            let session = try await sandbox.getSession()

            let parentId = try await session.child(path: "folder")
            let path = await session.path(for: "file.txt", parentId: parentId)
            #expect(path == "\(sandbox.mount.path())/folder/file.txt")
        }

        @Test func pathForNameInRootReturnsCombinedPath() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "file.txt")
            let session = try await sandbox.getSession()

            let path = await session.path(
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
            try sandbox.createFile(path: "file.txt", contents: contents)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "file.txt")
            let item = try await session.item(for: itemId)

            #expect(item.name == "file.txt")
            #expect(item.kind == .file)
            #expect(item.size == UInt64(contents.utf8.count))
            #expect(item.id == itemId)
        }

        @Test func itemForFolderSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(path: "folder")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "folder")
            let item = try await session.item(for: itemId)

            #expect(item.name == "folder")
            #expect(item.kind == .folder)
        }

        @Test func itemForSymlinkSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "target.txt")
            try sandbox.createSymlink(path: "symlink.txt", target: "target.txt")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "symlink.txt")
            let item = try await session.item(for: itemId)

            #expect(item.name == "symlink.txt")
            #expect(item.kind == .symlink(target: "target.txt"))
        }

        @Test func itemHasCorrectParent() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "folder/file.txt", contents: "data")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "folder/file.txt")
            let parentId = try await session.child(path: "folder")
            let item = try await session.item(for: itemId)

            #expect(item.parentId == parentId)
        }
    }

    struct ListTests {
        @Test func listReturnsFilesFoldersAndSymlinks() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "file.txt", contents: "hello")
            try sandbox.createFolder(path: "folder")
            try sandbox.createSymlink(path: "link.txt", target: "file.txt")
            let session = try await sandbox.getSession()

            let entries = try await session.list(for: .rootContainer)

            let fileEntry = try #require(
                entries.first { $0.name == "file.txt" }
            )
            #expect(fileEntry.kind == .file)

            let folderEntry = try #require(
                entries.first { $0.name == "folder" }
            )
            #expect(folderEntry.kind == .folder)

            let symlinkEntry = try #require(
                entries.first { $0.name == "link.txt" }
            )
            #expect(symlinkEntry.kind == .symlink(target: nil))
        }

        @Test func listEmptyDirectoryReturnsEmpty() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let entries = try await session.list(for: .rootContainer)

            #expect(entries.isEmpty)
        }

        @Test func listEntriesHaveCorrectParent() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "folder/child.txt", contents: "data")
            let session = try await sandbox.getSession()

            let parentId = try await session.child(path: "folder")
            let entries = try await session.list(for: parentId)

            let child = try #require(
                entries.first { $0.name == "child.txt" }
            )
            #expect(child.parentId == parentId)
        }
    }

    struct AttributesTests {
        @Test func attributesForFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let contents = "Hello, World!"
            try sandbox.createFile(path: "file.txt", contents: contents)
            let session = try await sandbox.getSession()

            let attrs = try await session.attributes(
                for: session.child(path: "file.txt")
            )

            #expect(attrs.type == .regular)
            #expect(attrs.size == UInt64(contents.utf8.count))
        }

        @Test func attributesForFolderSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(path: "folder")
            let session = try await sandbox.getSession()

            let attrs = try await session.attributes(
                for: session.child(path: "folder")
            )

            #expect(attrs.type == .directory)
        }

        @Test func attributesForMissingFileThrowsNoSuchItem() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "missing.txt", contents: "Hello!")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "missing.txt")
            try sandbox.removeItem(path: "missing.txt")

            await #expect(throws: AgentError.itemNotFound(itemId.rawValue)) {
                try await session.attributes(for: itemId)
            }
        }
    }

    struct SetAttributesTests {
        @Test func setPermissionsSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "perms.txt", contents: "test")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "perms.txt")
            try await session.setAttributes(for: itemId, permissions: 0o644)

            let attrs = try await session.attributes(for: itemId)
            let permissions = try #require(attrs.permissions)
            #expect(permissions & 0o777 == 0o644)
        }

        @Test func setModifyTimeSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "modify-time.txt", contents: "test")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "modify-time.txt")
            let date = Date(timeIntervalSince1970: 1_000_000)
            try await session.setAttributes(for: itemId, modifyTime: date)

            let attrs = try await session.attributes(for: itemId)
            #expect(attrs.modifyTime == date)
        }

        @Test func setAccessTimeSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "access-time.txt", contents: "test")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "access-time.txt")
            let date = Date(timeIntervalSince1970: 2_000_000)
            try await session.setAttributes(for: itemId, accessTime: date)

            let attrs = try await session.attributes(for: itemId)
            #expect(attrs.accessTime == date)
        }

        @Test func setAttributesForMissingFileThrows() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "missing.txt", contents: "Hello!")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "missing.txt")
            try sandbox.removeItem(path: "missing.txt")

            await #expect(throws: AgentError.itemNotFound(itemId.rawValue)) {
                try await session.setAttributes(for: itemId, permissions: 0o644)
            }
        }
    }

    struct CreateDirectoryTests {
        @Test func createDirectorySucceeds() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let name = "new-dir"
            let item = try await session.createDirectory(
                parentId: .rootContainer,
                name: name,
                mode: 0o755
            )

            #expect(item.name == name)
            #expect(item.kind == .folder)
            let attrs = try await session.attributes(for: item.id)
            #expect(attrs.type == .directory)
            let permissions = try #require(attrs.permissions)
            #expect(permissions & 0o777 == 0o755)
        }

        @Test func createDirectoryWithIfExistsSucceedDoesNotThrow() async throws
        {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let name = "existing-dir"
            try sandbox.createFolder(path: name)

            let item = try await session.createDirectory(
                parentId: .rootContainer,
                name: name,
                ifExists: .succeed
            )

            #expect(item.name == name)
            #expect(item.kind == .folder)
        }

        @Test func createDirectoryWhenExistsThrowsByDefault() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let name = "already-exists"
            try sandbox.createFolder(path: name)

            await #expect {
                try await session.createDirectory(
                    parentId: .rootContainer,
                    name: name
                )
            } throws: { error in
                guard case AgentError.filenameCollision = error else {
                    return false
                }
                return true
            }
        }

        @Test func createDirectoryInsertsRowMatchingItemId() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let name = "row-match-dir"
            let item = try await session.createDirectory(
                parentId: .rootContainer,
                name: name
            )

            let lookedUpId = try await session.child(
                of: .rootContainer,
                path: name
            )
            #expect(lookedUpId == item.id)
        }

        @Test func createDirectoryFailureLeavesNoRow() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let name = "collide-dir"
            try sandbox.createFolder(path: name)

            await #expect(throws: AgentError.filenameCollision) {
                _ = try await session.createDirectory(
                    parentId: .rootContainer,
                    name: name
                )
            }

            await #expect(
                throws: AgentError.itemNotFound(
                    NSFileProviderItemIdentifier.rootContainer.rawValue
                )
            ) {
                _ = try await session.child(of: .rootContainer, path: name)
            }
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
        }

        @Test func createSymlinkInsertsRowMatchingItemId() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let item = try await session.createSymlink(
                parentId: .rootContainer,
                name: "link",
                target: "/dev/null"
            )

            let lookedUpId = try await session.child(
                of: .rootContainer,
                path: "link"
            )
            #expect(lookedUpId == item.id)
        }

        @Test func createSymlinkFailureLeavesNoRow() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let name = "collide"
            try sandbox.createFile(path: name, contents: "data")

            await #expect(throws: (any Error).self) {
                _ = try await session.createSymlink(
                    parentId: .rootContainer,
                    name: name,
                    target: "/dev/null"
                )
            }

            await #expect(
                throws: AgentError.itemNotFound(
                    NSFileProviderItemIdentifier.rootContainer.rawValue
                )
            ) {
                _ = try await session.child(of: .rootContainer, path: name)
            }
        }
    }

    struct MoveTests {
        @Test func moveRenamesFile() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "original.txt", contents: "hello")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "original.txt")

            try await session.move(
                itemId,
                toParent: .rootContainer,
                name: "renamed.txt"
            )

            let newId = try await session.child(path: "renamed.txt")
            #expect(itemId == newId)
            let attrs = try await session.attributes(for: newId)
            #expect(attrs.type == .regular)
        }

        @Test func moveToNewParent() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "file.txt", contents: "hello")
            try sandbox.createFolder(path: "dest")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "file.txt")
            let destId = try await session.child(path: "dest")

            try await session.move(
                itemId,
                toParent: destId,
                name: "file.txt"
            )

            let movedId = try await session.child(path: "dest/file.txt")
            #expect(itemId == movedId)
            let attrs = try await session.attributes(for: movedId)
            #expect(attrs.type == .regular)
        }

        @Test func moveToNewParentAndRename() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "old.txt", contents: "hello")
            try sandbox.createFolder(path: "dest")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "old.txt")
            let destId = try await session.child(path: "dest")

            try await session.move(
                itemId,
                toParent: destId,
                name: "new.txt"
            )

            let parent = try await session.parent(of: itemId)
            #expect(parent == destId)

            let name = try await session.name(of: itemId)
            #expect(name == "new.txt")
        }
    }

    struct RemoveFileTests {
        @Test func removeFileSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "delete.txt")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "delete.txt")
            try await session.removeFile(for: itemId)

            #expect(!sandbox.exists(path: "delete.txt"))
        }

        @Test func removeFileMissingThrows() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "missing.txt")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "missing.txt")
            try await session.removeFile(for: itemId)

            await #expect(throws: AgentError.itemNotFound(itemId.rawValue)) {
                try await session.removeFile(for: itemId)
            }
        }
    }

    struct RemoveDirectoryTests {
        @Test func removeDirectorySucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFolder(path: "delete")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "delete")
            try await session.removeDirectory(for: itemId)

            #expect(!sandbox.exists(path: "delete"))
        }

        @Test func removeDirectoryWithContentsSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "non-empty/child.txt")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "non-empty")
            try await session.removeDirectory(for: itemId)

            #expect(!sandbox.exists(path: "non-empty"))
        }
    }

    struct UploadTests {
        @Test func uploadSmallFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let uploadUrl = sandbox.shared.appending(path: UUID().uuidString)
            let data = "Hello, World!\n"
            try data.write(to: uploadUrl, atomically: false, encoding: .utf8)

            let filename = "small-file.txt"
            let url = sandbox.getUrl(path: filename)
            let session = try await sandbox.getSession()

            let progress = Progress()
            let item = try await session.upload(
                parentId: .rootContainer,
                name: filename,
                file: uploadUrl,
                mode: 0o600,
                progress: progress
            )
            let currId = try await session.child(
                of: .rootContainer,
                path: filename
            )

            #expect(item.name == filename)
            #expect(item.size == UInt64(data.utf8.count))
            #expect(FileManager.default.fileExists(at: url))
            #expect(try String(contentsOf: url, encoding: .utf8) == data)
            #expect(progress.isFinished)
            #expect(try FileManager.default.permissions(of: url) == 0o600)
            #expect(currId == item.id)
        }

        @Test func uploadLargeFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let uploadUrl = sandbox.shared.appending(path: UUID().uuidString)
            let data = Data(count: 10_485_760)
            try data.write(to: uploadUrl)

            let filename = "large-file.txt"
            let url = sandbox.getUrl(path: filename)
            let session = try await sandbox.getSession()

            let progress = Progress()
            let item = try await session.upload(
                parentId: .rootContainer,
                name: filename,
                file: uploadUrl,
                mode: 0o600,
                progress: progress
            )
            let currId = try await session.child(
                of: .rootContainer,
                path: filename
            )

            #expect(item.name == filename)
            #expect(item.size == UInt64(data.count))
            #expect(FileManager.default.fileExists(at: url))
            #expect(try Data(contentsOf: url) == data)
            #expect(progress.isFinished)
            #expect(try FileManager.default.permissions(of: url) == 0o600)
            #expect(currId == item.id)
        }

        @Test func uploadFailureLeavesNoRow() async throws {
            let sandbox = TestSandbox()
            let session = try await sandbox.getSession()

            let name = "collide-upload"

            // Pre-create a directory at the upload target so opening it as a
            // file for writing fails.
            try sandbox.createFolder(path: name)

            let uploadUrl = sandbox.shared.appending(path: UUID().uuidString)
            try Data("data".utf8).write(to: uploadUrl)

            await #expect(throws: (any Error).self) {
                _ = try await session.upload(
                    parentId: .rootContainer,
                    name: name,
                    file: uploadUrl,
                    mode: 0o600,
                    progress: Progress()
                )
            }

            await #expect(
                throws: AgentError.itemNotFound(
                    NSFileProviderItemIdentifier.rootContainer.rawValue
                )
            ) {
                _ = try await session.child(of: .rootContainer, path: name)
            }
        }

        @Test func uploadEmptyFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let uploadUrl = sandbox.shared.appending(path: UUID().uuidString)
            try Data().write(to: uploadUrl)

            let filename = "empty-file.txt"
            let url = sandbox.getUrl(path: filename)
            let session = try await sandbox.getSession()

            let progress = Progress()
            let item = try await session.upload(
                parentId: .rootContainer,
                name: filename,
                file: uploadUrl,
                mode: 0o600,
                progress: progress
            )
            let currId = try await session.child(
                of: .rootContainer,
                path: filename
            )

            #expect(item.name == filename)
            #expect(item.size == 0)
            #expect(FileManager.default.fileExists(at: url))
            #expect(try Data(contentsOf: url).isEmpty)
            #expect(progress.isFinished)
            #expect(try FileManager.default.permissions(of: url) == 0o600)
            #expect(currId == item.id)
        }
    }

    struct DownloadTests {
        @Test func downloadSmallFileSucceeds() async throws {
            let sandbox = TestSandbox()
            let data = "Hello, World!"
            try sandbox.createFile(path: "small-file.txt", contents: data)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "small-file.txt")
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
            try sandbox.createFile(path: "large-file.dat", data: data)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "large-file.dat")
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

        @Test func downloadEmptyFileSucceeds() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "empty-file.txt", contents: "")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "empty-file.txt")
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
            try sandbox.createFile(path: "small.dat", data: data)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "small.dat")
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
            try sandbox.createFile(path: "empty.dat", data: Data())
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "empty.dat")
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
            try sandbox.createFile(path: "two-chunk-range.dat", data: data)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "two-chunk-range.dat")
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
            try sandbox.createFile(path: "offset.dat", data: data)
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "offset.dat")
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
            try sandbox.createFile(path: "read-file.txt", contents: contents)
            let session = try await sandbox.getSession()

            let data = try await session.withFile(
                for: session.child(path: "read-file.txt"),
                accessType: .readOnly
            ) { fp in
                try await fp.read()
            }

            #expect(String(data: data, encoding: .utf8) == contents)
        }

        @Test func withFileMissingFileThrowsNoSuchItem() async throws {
            let sandbox = TestSandbox()
            try sandbox.createFile(path: "missing.txt", contents: "Hello!")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "missing.txt")
            try sandbox.removeItem(path: "missing.txt")

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
            try sandbox.createFile(path: "folder/file.txt", contents: "hello")
            try sandbox.createFolder(path: "folder/subfolder")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "folder")
            let names = try await session.withDirectory(for: itemId) { dir in
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
            try sandbox.createFolder(path: "empty")
            let session = try await sandbox.getSession()

            let itemId = try await session.child(path: "empty")
            let count = try await session.withDirectory(for: itemId) { dir in
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
