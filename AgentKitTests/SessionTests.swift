import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH
import Testing

@testable import AgentKit

private func getSession() async throws -> Session {
    let config = try TestData.getConnectionConfig()
    let ssh = try await SSHClient.connect(config: config)
    let sftp = try await ssh.sftp()
    let db = try await DomainDB.open(
        config: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    return Session(
        config: config,
        ssh: ssh,
        sftp: sftp,
        db: db,
    )
}

struct SessionTests {
    struct NameTests {
        @Test func filePropertyReturnsFilenameForSimpleItem() async throws {
            let session = try await getSession()
            let simpleFile = try await session.child(path: "file.txt")
            let name = try await session.name(of: simpleFile)
            #expect(name == "file.txt")
        }

        @Test func filePropertyReturnsFilenameForNestedItem() async throws {
            let session = try await getSession()
            let nestedFile = try await session.child(path: "folder/file.txt")
            let name = try await session.name(of: nestedFile)
            #expect(name == "file.txt")
        }
    }

    struct ParentTests {
        @Test func parentOfRootContainerIsRootContainer() async throws {
            let session = try await getSession()
            let parent = try await session.parent(of: .rootContainer)
            #expect(parent == .rootContainer)
        }

        @Test func parentOfTopLevelItemIsRootContainer() async throws {
            let session = try await getSession()
            let topLevel = try await session.child(path: "folder")
            let parent = try await session.parent(of: topLevel)
            #expect(parent == .rootContainer)
        }

        @Test func parentOfTrashContainerIsRootContainer() async throws {
            let session = try await getSession()
            let parent = try await session.parent(of: .trashContainer)
            #expect(parent == .rootContainer)
        }

        @Test func parentOfItemInTrashIsTrashContainer() async throws {
            let session = try await getSession()
            let itemInTrashes = try await session.child(path: ".Trashes/file")
            let parent = try await session.parent(of: itemInTrashes)
            #expect(parent == .trashContainer)
        }

        @Test func parentOfNestedItemIsParentFolder() async throws {
            let session = try await getSession()
            let nested = try await session.child(path: "folder/file")
            let actual = try await session.parent(of: nested)
            let expected = try await session.child(path: "folder")
            #expect(actual == expected)
        }

        @Test func parentOfDeeplyNestedItemIsImmediateParent() async throws {
            let session = try await getSession()
            let deeplyNested = try await session.child(path: "a/b/c")
            let actual = try await session.parent(of: deeplyNested)
            let expected = try await session.child(path: "a/b")
            #expect(actual == expected)
        }
    }

    struct ChildTests {
        @Test func childOfRootContainerWithNameTrashesIsTrashContainer()
            async throws
        {
            let session = try await getSession()
            let childOfRoot = try await session.child(path: ".Trashes")
            #expect(childOfRoot == .trashContainer)
        }

        @Test func childOfTrashContainerReturnsItemInTrashes() async throws {
            let session = try await getSession()
            let actual = try await session.child(
                of: .trashContainer,
                path: "file"
            )
            let expected = try await session.child(path: ".Trashes/file")
            #expect(actual == expected)
        }

        @Test func childOfItemReturnsNestedItem() async throws {
            let session = try await getSession()
            let parent = try await session.child(path: "folder")
            let actual = try await session.child(of: parent, path: "file")
            let expected = try await session.child(path: "folder/file")
            #expect(actual == expected)
        }
    }

    struct PathTests {
        @Test func pathForRootContainerReturnsConfigPath() async throws {
            let session = try await getSession()
            let path = await session.path(for: .rootContainer)
            #expect(path == TestData.mount.path())
        }

        @Test func pathForItemReturnsCombinedPath() async throws {
            let session = try await getSession()
            let itemId = try await session.child(path: "folder/file.txt")
            let path = await session.path(for: itemId)
            #expect(path == "\(TestData.mount.path())/folder/file.txt")
        }

        @Test func pathForNameInParentReturnsCombinedPath() async throws {
            let session = try await getSession()
            let parentId = try await session.child(path: "folder")
            let path = await session.path(for: "file.txt", parentId: parentId)
            #expect(path == "\(TestData.mount.path())/folder/file.txt")
        }

        @Test func pathForNameInRootReturnsCombinedPath() async throws {
            let session = try await getSession()
            let path = await session.path(
                for: "file.txt",
                parentId: .rootContainer
            )
            #expect(path == "\(TestData.mount.path())/file.txt")
        }
    }

    struct InfoTests {
        let testFolderPath = "session-info"

        init() throws {
            try TestData.createFolder(path: testFolderPath)
        }

        @Test func infoForFileSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/file.txt"
            let contents = "Hello, World!"
            try TestData.createFile(path: path, contents: contents)

            let itemId = try await session.child(path: path)
            let info = try await session.info(for: itemId)

            #expect(info.name == "file.txt")
            #expect(info.type == .file)
            #expect(info.size == UInt64(contents.utf8.count))
            #expect(info.id == itemId.rawValue)
        }

        @Test func infoForFolderSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/folder"
            try TestData.createFolder(path: path)

            let itemId = try await session.child(path: path)
            let info = try await session.info(for: itemId)

            #expect(info.name == "folder")
            #expect(info.type == .folder)
        }
        
        @Test func infoForSymlinkSucceeds() async throws {
            let session = try await getSession()

            let target = "\(testFolderPath)/info-symlink-target.txt"
            let contents = "Hello, World!"
            try TestData.createFile(path: target, contents: contents)
            let symlink = "\(testFolderPath)/info-symlink-link.txt"
            try TestData.createSymlink(path: symlink, target: target)

            let itemId = try await session.child(path: symlink)
            let info = try await session.info(for: itemId)

            #expect(info.name == "info-symlink-link.txt")
            #expect(info.type == .symlink(target: target))
        }

        @Test func infoHasCorrectParent() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/nested/file.txt"
            try TestData.createFile(path: path, contents: "data")

            let itemId = try await session.child(path: path)
            let parentId = try await session.child(
                path: "\(testFolderPath)/nested"
            )
            let info = try await session.info(for: itemId)

            #expect(info.parentId == parentId.rawValue)
        }
    }

    struct ListTests {
        let testFolderPath = "session-list"

        init() throws {
            try TestData.createFolder(path: testFolderPath)
        }

        @Test func listReturnsFilesFoldersAndSymlinks() async throws {
            let session = try await getSession()

            try TestData.createFile(
                path: "\(testFolderPath)/file.txt",
                contents: "hello"
            )
            try TestData.createFolder(
                path: "\(testFolderPath)/subfolder"
            )
            try TestData.createSymlink(
                path: "\(testFolderPath)/link.txt",
                target: "file.txt"
            )

            let itemId = try await session.child(path: testFolderPath)
            let entries = try await session.list(for: itemId)

            let names = Set(entries.map(\.name))
            #expect(names.contains("file.txt"))
            #expect(names.contains("subfolder"))

            let fileEntry = try #require(
                entries.first { $0.name == "file.txt" }
            )
            #expect(fileEntry.type == .file)

            let folderEntry = try #require(
                entries.first { $0.name == "subfolder" }
            )
            #expect(folderEntry.type == .folder)

            let symlinkEntry = try #require(
                entries.first { $0.name == "link.txt" }
            )
            #expect(symlinkEntry.type == .symlink(target: "file.txt"))
        }

        @Test func listEmptyDirectoryReturnsEmpty() async throws {
            let session = try await getSession()

            let emptyPath = "\(testFolderPath)/empty"
            try TestData.createFolder(path: emptyPath)

            let itemId = try await session.child(path: emptyPath)
            let entries = try await session.list(for: itemId)

            #expect(entries.isEmpty)
        }

        @Test func listEntriesHaveCorrectParent() async throws {
            let session = try await getSession()

            try TestData.createFile(
                path: "\(testFolderPath)/child.txt",
                contents: "data"
            )

            let parentId = try await session.child(path: testFolderPath)
            let entries = try await session.list(for: parentId)

            let child = try #require(
                entries.first { $0.name == "child.txt" }
            )
            #expect(child.parentId == parentId.rawValue)
        }
    }

    struct ExistsTests {
        let testFolderPath = "session-exists"

        init() throws {
            try TestData.createFolder(path: testFolderPath)
        }

        @Test func existsReturnsTrueForExistingFile() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/file.txt"
            try TestData.createFile(path: path, contents: "data")

            let itemId = try await session.child(path: path)
            let result = await session.exists(for: itemId)
            #expect(result == true)
        }

        @Test func existsReturnsFalseForMissingFile() async throws {
            let session = try await getSession()

            let itemId = try await session.child(
                path: "\(testFolderPath)/missing.txt"
            )
            let result = await session.exists(for: itemId)
            #expect(result == false)
        }
    }

    struct AttributesTests {
        let testFolderPath = "session-attributes"
        let testFolderUrl: URL

        init() throws {
            testFolderUrl = try TestData.createFolder(path: testFolderPath)
        }

        @Test func attributesForFileSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/file.txt"
            let contents = "Hello, World!"
            try TestData.createFile(path: path, contents: contents)

            let attrs = try await session.attributes(
                for: session.child(path: path)
            )

            #expect(attrs.type == .regular)
            #expect(attrs.size == UInt64(contents.utf8.count))
        }

        @Test func attributesForFolderSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/folder"
            try TestData.createFolder(path: path)

            let attrs = try await session.attributes(
                for: session.child(path: path)
            )

            #expect(attrs.type == .directory)
        }

        @Test func attributesForMissingFileThrowsNoSuchItem() async throws {
            let session = try await getSession()

            let parentId = try await session.child(path: testFolderPath)

            await #expect(throws: AgentError.itemNotFound(parentId.rawValue)) {
                try await session.attributes(
                    for: session.child(
                        path: "\(testFolderPath)/missing.txt",
                        ifNotExists: .fail
                    )
                )
            }
        }
    }

    struct SetAttributesTests {
        let testFolderPath = "session-set-attributes"

        init() throws {
            try TestData.createFolder(path: testFolderPath)
        }

        @Test func setPermissionsSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/perms.txt"
            try TestData.createFile(path: path, contents: "test")
            let itemId = try await session.child(path: path)

            try await session.setAttributes(
                for: itemId,
                permissions: 0o644
            )

            let attrs = try await session.attributes(for: itemId)
            let permissions = try #require(attrs.permissions)
            #expect(permissions & 0o777 == 0o644)
        }

        @Test func setModifyTimeSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/modify-time.txt"
            try TestData.createFile(path: path, contents: "test")
            let itemId = try await session.child(path: path)

            let date = Date(timeIntervalSince1970: 1_000_000)
            try await session.setAttributes(
                for: itemId,
                modifyTime: date
            )

            let attrs = try await session.attributes(for: itemId)
            #expect(attrs.modifyTime == date)
        }

        @Test func setAccessTimeSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/access-time.txt"
            try TestData.createFile(path: path, contents: "test")
            let itemId = try await session.child(path: path)

            let date = Date(timeIntervalSince1970: 2_000_000)
            try await session.setAttributes(
                for: itemId,
                accessTime: date
            )

            let attrs = try await session.attributes(for: itemId)
            #expect(attrs.accessTime == date)
        }

        @Test func setAttributesForMissingFileThrows() async throws {
            let session = try await getSession()

            let parentId = try await session.child(path: testFolderPath)

            await #expect(throws: AgentError.itemNotFound(parentId.rawValue)) {
                try await session.setAttributes(
                    for: session.child(
                        path: "\(testFolderPath)/missing.txt",
                        ifNotExists: .fail
                    ),
                    permissions: 0o644
                )
            }
        }
    }

    struct CreateDirectoryTests {
        let testFolderPath = "session-create-directory"

        init() throws {
            try TestData.createFolder(path: testFolderPath)
        }

        @Test func createDirectorySucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/new-dir"
            let itemId = try await session.child(path: path)

            try await session.createDirectory(for: itemId, mode: 0o755)

            let attrs = try await session.attributes(for: itemId)
            #expect(attrs.type == .directory)
            let permissions = try #require(attrs.permissions)
            #expect(permissions & 0o777 == 0o755)
        }

        @Test func createDirectoryWithIfExistsSucceedDoesNotThrow() async throws
        {
            let session = try await getSession()

            let path = "\(testFolderPath)/existing-dir"
            try TestData.createFolder(path: path)
            let itemId = try await session.child(path: path)

            try await session.createDirectory(
                for: itemId,
                ifExists: .succeed
            )
        }

        @Test func createDirectoryWhenExistsThrowsByDefault() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/already-exists"
            try TestData.createFolder(path: path)
            let itemId = try await session.child(path: path)

            await #expect {
                try await session.createDirectory(for: itemId)
            } throws: { error in
                guard case AgentError.filenameCollision = error else {
                    return false
                }
                return true
            }
        }
    }

    struct MoveTests {
        let testFolderPath = "session-move"

        init() throws {
            try TestData.createFolder(path: testFolderPath)
        }

        @Test func moveRenamesFile() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/original.txt"
            try TestData.createFile(path: path, contents: "hello")
            let itemId = try await session.child(path: path)
            let parentId = try await session.child(path: testFolderPath)

            try await session.move(
                itemId,
                toParent: parentId,
                name: "renamed.txt"
            )

            let newId = try await session.child(
                path: "\(testFolderPath)/renamed.txt",
                ifNotExists: .fail
            )
            let attrs = try await session.attributes(for: newId)
            #expect(attrs.type == .regular)
        }

        @Test func moveToNewParent() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/to-move.txt"
            try TestData.createFile(path: path, contents: "hello")
            let itemId = try await session.child(path: path)

            let destPath = "\(testFolderPath)/dest"
            try TestData.createFolder(path: destPath)
            let destId = try await session.child(path: destPath)

            try await session.move(
                itemId,
                toParent: destId,
                name: "to-move.txt"
            )

            let movedId = try await session.child(
                path: "\(testFolderPath)/dest/to-move.txt",
                ifNotExists: .fail
            )
            let attrs = try await session.attributes(for: movedId)
            #expect(attrs.type == .regular)
        }

        @Test func moveCreatesParentWhenRequested() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/create-parent.txt"
            try TestData.createFile(path: path, contents: "hello")
            let itemId = try await session.child(path: path)

            let newParentId = try await session.child(
                path: "\(testFolderPath)/new-parent"
            )

            try await session.move(
                itemId,
                toParent: newParentId,
                name: "create-parent.txt",
                ifParentNotExists: .create
            )

            let movedId = try await session.child(
                path: "\(testFolderPath)/new-parent/create-parent.txt",
                ifNotExists: .fail
            )
            let attrs = try await session.attributes(for: movedId)
            #expect(attrs.type == .regular)
        }

        @Test func moveUpdatesDbParentAndName() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/db-check.txt"
            try TestData.createFile(path: path, contents: "hello")
            let itemId = try await session.child(path: path)

            let destPath = "\(testFolderPath)/db-dest"
            try TestData.createFolder(path: destPath)
            let destId = try await session.child(path: destPath)

            try await session.move(
                itemId,
                toParent: destId,
                name: "new-name.txt"
            )

            let parent = try await session.parent(of: itemId)
            #expect(parent == destId)

            let name = try await session.name(of: itemId)
            #expect(name == "new-name.txt")
        }
    }

    struct RemoveFileTests {
        let testFolderPath = "session-remove-file"

        init() throws {
            try TestData.createFolder(path: testFolderPath)
        }

        @Test func removeFileSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/to-delete.txt"
            try TestData.createFile(path: path, contents: "bye")
            let itemId = try await session.child(path: path)

            try await session.removeFile(for: itemId)

            let exists = await session.exists(for: itemId)
            #expect(!exists)
        }

        @Test func removeFileMissingThrows() async throws {
            let session = try await getSession()

            let itemId = try await session.child(
                path: "\(testFolderPath)/nonexistent.txt"
            )

            let exists = await session.exists(for: itemId)
            #expect(!exists)
        }
    }

    struct RemoveDirectoryTests {
        let testFolderPath = "session-remove-dir"

        init() throws {
            try TestData.createFolder(path: testFolderPath)
        }

        @Test func removeDirectorySucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/to-delete"
            try TestData.createFolder(path: path)
            let itemId = try await session.child(path: path)

            try await session.removeDirectory(for: itemId)

            let exists = await session.exists(for: itemId)
            #expect(!exists)
        }

        @Test func removeDirectoryWithContentsSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/non-empty"
            try TestData.createFile(
                path: "\(path)/child.txt",
                contents: "nested"
            )
            let itemId = try await session.child(path: path)

            try await session.removeDirectory(for: itemId)

            let exists = await session.exists(for: itemId)
            #expect(!exists)
        }
    }

    struct UploadTests {
        let testFolderPath = "session-upload-file"
        let testFolderUrl: URL

        init() throws {
            testFolderUrl = try TestData.createFolder(path: testFolderPath)
        }

        @Test func uploadSmallFileSucceeds() async throws {
            let session = try await getSession()

            let uploadUrl = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
            let data = "Hello, World!\n"
            try data.write(to: uploadUrl, atomically: false, encoding: .utf8)

            let filePath = "\(testFolderPath)/small-file.txt"
            try TestData.removeItem(path: filePath)
            let url = TestData.getUrl(path: filePath)

            let itemId = try await session.child(path: filePath)
            let progress = Progress()
            try await session.upload(
                itemId: itemId,
                file: uploadUrl,
                mode: 0o600,
                progress: progress
            )

            #expect(FileManager.default.fileExists(at: url))
            #expect(try String(contentsOf: url, encoding: .utf8) == data)
            #expect(progress.isFinished)
            #expect(try FileManager.default.permissions(of: url) == 0o600)
        }

        @Test func uploadLargeFileSucceeds() async throws {
            let session = try await getSession()

            let uploadUrl = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
            let data = Data(count: 10_485_760)
            try data.write(to: uploadUrl)

            let filePath = "\(testFolderPath)/large-file.txt"
            try TestData.removeItem(path: filePath)
            let url = TestData.getUrl(path: filePath)

            let itemId = try await session.child(path: filePath)
            let progress = Progress()
            try await session.upload(
                itemId: itemId,
                file: uploadUrl,
                mode: 0o600,
                progress: progress
            )

            #expect(FileManager.default.fileExists(at: url))
            #expect(try Data(contentsOf: url) == data)
            #expect(progress.isFinished)
            #expect(try FileManager.default.permissions(of: url) == 0o600)
        }

        @Test func uploadEmptyFileSucceeds() async throws {
            let session = try await getSession()

            let uploadUrl = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
            try Data().write(to: uploadUrl)

            let filePath = "\(testFolderPath)/empty-file.txt"
            try TestData.removeItem(path: filePath)
            let url = TestData.getUrl(path: filePath)

            let itemId = try await session.child(path: filePath)
            let progress = Progress()
            try await session.upload(
                itemId: itemId,
                file: uploadUrl,
                mode: 0o600,
                progress: progress
            )

            #expect(FileManager.default.fileExists(at: url))
            #expect(try Data(contentsOf: url).isEmpty)
            #expect(progress.isFinished)
            #expect(try FileManager.default.permissions(of: url) == 0o600)
        }
    }

    struct DownloadTests {
        let testFolderPath = "session-download-file"
        let testFolderUrl: URL

        init() throws {
            testFolderUrl = try TestData.createFolder(path: testFolderPath)
        }

        @Test func downloadSmallFileSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/small-file.txt"
            let data = "Hello, World!"
            try TestData.createFile(path: path, contents: data)

            let itemId = try await session.child(path: path)
            let progress = Progress()
            let (url, item) = try await session.download(
                itemId: itemId,
                progress: progress
            )

            #expect(item.name == "small-file.txt")
            #expect(item.type == .file)
            let size = try #require(item.size)
            #expect(size == data.count)
            #expect(try String(contentsOf: url, encoding: .utf8) == data)
            #expect(progress.isFinished)
        }

        @Test func downloadLargeFileSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/large-file.dat"
            let data = Data(count: 10_485_760)
            try TestData.createFile(path: path, data: data)

            let itemId = try await session.child(path: path)
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
            let session = try await getSession()

            let path = "\(testFolderPath)/empty-file.txt"
            try TestData.createFile(path: path, contents: "")

            let itemId = try await session.child(path: path)
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
        let testFolderPath = "session-stream"
        let chunkSize = File.defaultChunkSize

        init() throws {
            try TestData.createFolder(path: testFolderPath)
        }

        @Test func streamSmallFileSucceeds() async throws {
            let session = try await getSession()

            let data = Data(repeating: 0xAB, count: Int(chunkSize))
            let path = "\(testFolderPath)/small.dat"
            try TestData.createFile(path: path, data: data)

            let itemId = try await session.child(path: path)
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
            let session = try await getSession()

            let path = "\(testFolderPath)/empty.dat"
            try TestData.createFile(path: path, data: Data())

            let itemId = try await session.child(path: path)
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
            let session = try await getSession()

            let data = Data(count: Int(chunkSize) * 2)
            let path = "\(testFolderPath)/two-chunk-range.dat"
            try TestData.createFile(path: path, data: data)

            let itemId = try await session.child(path: path)
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
            let session = try await getSession()

            // Two-chunk file: first chunk 0xAA, second chunk 0xBB
            let data =
                Data(repeating: 0xAA, count: Int(chunkSize))
                + Data(repeating: 0xBB, count: Int(chunkSize))
            let path = "\(testFolderPath)/offset.dat"
            try TestData.createFile(path: path, data: data)

            let itemId = try await session.child(path: path)
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
        let testFolderPath = "session-with-file"
        let testFolderUrl: URL

        init() throws {
            testFolderUrl = try TestData.createFolder(path: testFolderPath)
        }

        @Test func withFileReadSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/read-file.txt"
            let contents = "Hello, World!"
            try TestData.createFile(path: path, contents: contents)

            let data = try await session.withFile(
                for: session.child(path: path),
                accessType: .readOnly
            ) { fp in
                try await fp.read()
            }

            #expect(String(data: data, encoding: .utf8) == contents)
        }

        @Test func withFileMissingFileThrowsNoSuchItem() async throws {
            let session = try await getSession()

            let itemId = try await session.child(
                path: "\(testFolderPath)/missing.txt"
            )

            await #expect(throws: AgentError.itemNotFound(itemId.rawValue)) {
                try await session.withFile(for: itemId, accessType: .readOnly) {
                    _ in
                }
            }
        }
    }

    struct WithDirectoryTests {
        let testFolderPath = "session-with-directory"

        init() throws {
            try TestData.createFolder(path: testFolderPath)
        }

        @Test func withDirectoryListsEntries() async throws {
            let session = try await getSession()

            try TestData.createFile(
                path: "\(testFolderPath)/file.txt",
                contents: "hello"
            )
            try TestData.createFolder(path: "\(testFolderPath)/subfolder")

            let itemId = try await session.child(path: testFolderPath)
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
            let session = try await getSession()

            let emptyPath = "\(testFolderPath)/empty"
            try TestData.createFolder(path: emptyPath)

            let itemId = try await session.child(path: emptyPath)
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
