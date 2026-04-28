import Common
import FileProvider
import Foundation
import SwiftLibSSH
import Testing

@testable import AgentKit

private func getSession() async throws -> Session {
    DomainDB.urlFactory = { _ in TestData.domainDbStorePath }
    try await TestData.initAppDB()

    let config = try TestData.getConnectionConfig()
    let ssh = try await SSHClient.connect(config: config)
    let sftp = try await ssh.sftp()
    let db = try await TestData.getDomainDb()

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
            #expect(!info.isDirectory)
            #expect(info.size == UInt64(contents.utf8.count))
            #expect(info.id == itemId.rawValue)
        }

        @Test func infoForDirectorySucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/folder"
            try TestData.createFolder(path: path)

            let itemId = try await session.child(path: path)
            let info = try await session.info(for: itemId)

            #expect(info.name == "folder")
            #expect(info.isDirectory)
        }

        @Test func infoHasCorrectParent() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/nested/file.txt"
            try TestData.createFile(path: path, contents: "data")

            let itemId = try await session.child(path: path)
            let parentId = try await session.child(path: "\(testFolderPath)/nested")
            let info = try await session.info(for: itemId)

            #expect(info.parentId == parentId.rawValue)
        }
    }

    struct ListTests {
        let testFolderPath = "session-list"

        init() throws {
            try TestData.createFolder(path: testFolderPath)
        }

        @Test func listReturnsFilesAndFolders() async throws {
            let session = try await getSession()

            try TestData.createFile(
                path: "\(testFolderPath)/file.txt",
                contents: "hello"
            )
            try TestData.createFolder(path: "\(testFolderPath)/subfolder")

            let itemId = try await session.child(path: testFolderPath)
            let entries = try await session.list(for: itemId)

            let names = Set(entries.map(\.name))
            #expect(names.contains("file.txt"))
            #expect(names.contains("subfolder"))

            let fileEntry = try #require(
                entries.first { $0.name == "file.txt" }
            )
            #expect(!fileEntry.isDirectory)

            let folderEntry = try #require(
                entries.first { $0.name == "subfolder" }
            )
            #expect(folderEntry.isDirectory)
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
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
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

            await #expect {
                try await session.attributes(
                    for: session.child(
                        path: "\(testFolderPath)/missing.txt",
                        ifNotExists: .fail
                    )
                )
            } throws: { error in isNoSuchItemError(error) }
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
            #expect(attrs.permissions & 0o777 == 0o644)
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

            await #expect {
                try await session.setAttributes(
                    for: session.child(
                        path: "\(testFolderPath)/missing.txt",
                        ifNotExists: .fail
                    ),
                    permissions: 0o644
                )
            } throws: { error in isNoSuchItemError(error) }
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
            #expect(attrs.permissions & 0o777 == 0o755)
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
                (error as NSError).domain == NSFileProviderErrorDomain
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

            await #expect {
                try await session.attributes(for: itemId)
            } throws: { error in isNoSuchItemError(error) }
        }

        @Test func removeFileMissingThrows() async throws {
            let session = try await getSession()

            let itemId = try await session.child(
                path: "\(testFolderPath)/nonexistent.txt"
            )

            await #expect {
                try await session.removeFile(for: itemId)
            } throws: { error in isNoSuchItemError(error) }
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

            await #expect {
                try await session.attributes(for: itemId)
            } throws: { error in isNoSuchItemError(error) }
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

            await #expect {
                try await session.attributes(for: itemId)
            } throws: { error in isNoSuchItemError(error) }
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

    struct WithFileTests {
        let testFolderPath = "session-with-file"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func withFileReadSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/read-file.txt"
            let contents = "Hello, World!"
            try TestData.createFile(path: path, contents: contents)

            let data = try await session.withFile(
                for: session.child(path: path),
                accessType: .readOnly
            ) { file in
                try await file.read()
            }

            #expect(String(data: data, encoding: .utf8) == contents)
        }

        @Test func withFileMissingFileThrowsNoSuchItem() async throws {
            let session = try await getSession()

            await #expect {
                try await session.withFile(
                    for: session.child(
                        path: "\(testFolderPath)/missing.txt"
                    ),
                    accessType: .readOnly
                ) { _ in }
            } throws: { error in isNoSuchItemError(error) }
        }
    }
}

func isNoSuchItemError(_ error: any Error) -> Bool {
    (error as NSError).code == NSFileProviderError.noSuchItem.rawValue
        && (error as NSError).domain == NSFileProviderErrorDomain
}
