import Common
import FileProvider
import SwiftData
import SwiftLibSSH
import Synchronization
import Testing
import UniformTypeIdentifiers

@testable import ExtensionKit

private func getSession() async throws -> Session {
    Session.agentClientFactory = TestData.getAgentClient
    DomainDB.urlFactory = { _ in TestData.domainDbStorePath }
    try await TestData.initAppDB()

    let domain = NSFileProviderDomain(
        identifier: NSFileProviderDomainIdentifier("test"),
        displayName: TestData.name
    )
    let config = try TestData.getConnectionConfig()
    let ssh = try await SSHClient.connect(config: config)
    let sftp = try await ssh.sftp()
    let db = try await TestData.getDomainDb()

    return Session(
        domain: domain,
        config: config,
        ssh: ssh,
        sftp: sftp,
        db: db,
    )
}

// TODO: Remove this after migration to agent in main app
@Suite(.serialized)
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

    struct ItemTests {
        let testFolderPath = "session-item"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func itemForFileSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/file.txt"
            let contents = "Hello, World!"
            try TestData.createFile(path: path, contents: contents)

            let item = try await session.item(
                for: session.child(path: path)
            )

            #expect(item.filename == "file.txt")
            #expect(item.contentType == .text)
            #expect(item.documentSize?.intValue == contents.utf8.count)
        }

        @Test func itemForFolderSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/folder"
            try TestData.createFolder(path: path)

            let item = try await session.item(
                for: session.child(path: path)
            )

            #expect(item.filename == "folder")
            #expect(item.contentType == .folder)
        }

        @Test func itemForRootSucceeds() async throws {
            let session = try await getSession()

            let item = try await session.item(for: .rootContainer)

            #expect(
                item.filename == ""
            )
            #expect(item.contentType == .folder)
        }

        @Test func itemForMissingFileThrowsNoSuchItem() async throws {
            let session = try await getSession()

            await #expect {
                try await session.item(
                    for: session.child(
                        path: "\(testFolderPath)/missing.txt"
                    )
                )
            } throws: { error in isNoSuchItemError(error) }
        }
    }

    struct AttributesTests {
        let testFolderPath = "session-attributes"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func setModifyTimeSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/modify-time.txt"
            try TestData.createFile(path: path, contents: "data")

            let newModifyTime = Date(timeIntervalSince1970: 1_000_000)
            try await session.setAttributes(
                for: session.child(path: path),
                modifyTime: newModifyTime
            )

            let fileURL = TestData.getUrl(path: path)
            let fileAttrs = try FileManager.default.attributesOfItem(
                atPath: fileURL.path()
            )
            let actualModifyTime = fileAttrs[.modificationDate] as? Date
            #expect(
                actualModifyTime?.timeIntervalSince1970
                    == newModifyTime.timeIntervalSince1970
            )
        }

        @Test func setAccessTimeSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/access-time.txt"
            try TestData.createFile(path: path, contents: "data")

            let newAccessTime = Date(timeIntervalSince1970: 2_000_000)
            try await session.setAttributes(
                for: session.child(path: path),
                accessTime: newAccessTime
            )

            let fileURL = TestData.getUrl(path: path)
            var st = stat()
            stat(fileURL.path(), &st)
            let actualAccessTime = Date(
                timeIntervalSince1970: TimeInterval(st.st_atimespec.tv_sec)
            )
            #expect(
                actualAccessTime.timeIntervalSince1970
                    == newAccessTime.timeIntervalSince1970
            )
        }

        @Test func setAttributesForMissingFileThrowsNoSuchItem() async throws {
            let session = try await getSession()

            await #expect {
                try await session.setAttributes(
                    for: session.child(
                        path: "\(testFolderPath)/missing.txt",
                        ifNotExists: .fail
                    ),
                    modifyTime: Date()
                )
            } throws: { error in isNoSuchItemError(error) }
        }
    }

    struct CreateDirectoryTests {
        let testFolderPath = "session-create-directory"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func createDirectorySucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/new-directory"
            try TestData.removeItem(path: path)
            let directoryURL = TestData.getUrl(path: path)
            #expect(
                !FileManager.default.fileExists(atPath: directoryURL.path())
            )

            try await session.createDirectory(
                for: session.child(path: path)
            )

            #expect(
                FileManager.default.fileExists(atPath: directoryURL.path())
            )
        }

        @Test func createExistingDirectoryIfExistsSetSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/existing-directory"
            try TestData.createFolder(path: path)
            let directoryURL = TestData.getUrl(path: path)

            try await session.createDirectory(
                for: session.child(path: path),
                ifExists: .succeed
            )

            #expect(
                FileManager.default.fileExists(atPath: directoryURL.path())
            )
        }

        @Test func createExistingDirectoryIfExistsNotSetThrows() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/existing-directory"
            try TestData.createFolder(path: path)

            await #expect {
                try await session.createDirectory(
                    for: session.child(path: path),
                    ifExists: .fail
                )
            } throws: { error in
                (error as NSError).code
                    == NSFileProviderError.filenameCollision.rawValue
                    && (error as NSError).domain == NSFileProviderErrorDomain
            }
        }
    }

    struct MoveTests {
        let testFolderPath = "session-move"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func moveFileSucceeds() async throws {
            let session = try await getSession()

            let sourcePath = "\(testFolderPath)/source.txt"
            try TestData.createFile(path: sourcePath, contents: "data")

            try TestData.removeItem(path: "\(testFolderPath)/destination.txt")

            let sourceId = try await session.child(path: sourcePath)
            let parentId = try await session.child(path: testFolderPath)

            try await session.move(
                sourceId,
                toParent: parentId,
                name: "destination.txt"
            )

            #expect(
                FileManager.default.fileExists(
                    atPath: TestData.getUrl(
                        path: "\(testFolderPath)/destination.txt"
                    ).path()
                )
            )
            #expect(
                !FileManager.default.fileExists(
                    atPath: TestData.getUrl(path: sourcePath).path()
                )
            )
            let name = try await session.name(of: sourceId)
            let parent = try await session.parent(of: sourceId)
            #expect(name == "destination.txt")
            #expect(parent == parentId)
        }

        @Test func moveMissingFileThrowsNoSuchItem() async throws {
            let session = try await getSession()

            let sourceId = try await session.child(
                path: "\(testFolderPath)/missing.txt"
            )
            let parentId = try await session.child(path: testFolderPath)

            await #expect {
                try await session.move(
                    sourceId,
                    toParent: parentId,
                    name: "destination.txt"
                )
            } throws: { error in isNoSuchItemError(error) }
        }

        @Test func moveToMissingParentThrowsNoSuchItem() async throws {
            let session = try await getSession()

            let sourcePath = "\(testFolderPath)/source-missing-parent-fail.txt"
            try TestData.createFile(path: sourcePath, contents: "data")

            try TestData.removeItem(
                path: "\(testFolderPath)/missing-parent-fail"
            )

            let sourceId = try await session.child(path: sourcePath)
            let parentId = try await session.child(
                path: "\(testFolderPath)/missing-parent-fail"
            )

            await #expect {
                try await session.move(
                    sourceId,
                    toParent: parentId,
                    name: "destination.txt",
                    ifParentNotExists: .fail
                )
            } throws: { error in isNoSuchItemError(error) }
        }

        @Test func moveToMissingParentForceCreateSucceeds() async throws {
            let session = try await getSession()

            let sourcePath = "\(testFolderPath)/source-missing-parent.txt"
            try TestData.createFile(path: sourcePath, contents: "data")

            try TestData.removeItem(
                path: "\(testFolderPath)/missing-parent"
            )

            let sourceId = try await session.child(path: sourcePath)
            let parentId = try await session.child(
                path: "\(testFolderPath)/missing-parent"
            )

            try await session.move(
                sourceId,
                toParent: parentId,
                name: "destination.txt",
                ifParentNotExists: .create
            )

            let destinationPath =
                "\(testFolderPath)/missing-parent/destination.txt"
            #expect(
                FileManager.default.fileExists(
                    atPath: TestData.getUrl(path: destinationPath).path()
                )
            )
            #expect(
                !FileManager.default.fileExists(
                    atPath: TestData.getUrl(path: sourcePath).path()
                )
            )
        }

    }

    struct ExistsTests {
        let testFolderPath = "session-exists"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func existsReturnsTrueForExistingFile() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/file.txt"
            try TestData.createFile(path: path, contents: "data")

            let result = await session.exists(
                for: try session.child(path: path)
            )
            #expect(result == true)
        }

        @Test func existsReturnsFalseForMissingFile() async throws {
            let session = try await getSession()

            let id = try await session.child(
                path: "\(testFolderPath)/missing.txt"
            )
            let result = await session.exists(for: id)
            #expect(result == false)
        }
    }

    struct EnumerateItemsTests {
        let testFolderPath = "session-enumerate"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func enumeratesFilesAndFolders() async throws {
            let session = try await getSession()

            try TestData.createFile(
                path: "\(testFolderPath)/file.txt",
                contents: "hello"
            )
            try TestData.createFolder(path: "\(testFolderPath)/subfolder")

            let items = Mutex<[any NSFileProviderItemProtocol]>([])
            try await session.enumerateItems(
                for: session.child(path: testFolderPath)
            ) { batch in
                items.withLock { $0.append(contentsOf: batch) }
            }

            let names = Set(items.withLock { $0 }.map(\.filename))
            #expect(names.contains("file.txt"))
            #expect(names.contains("subfolder"))
        }

        @Test func yieldedItemsHaveCorrectParent() async throws {
            let session = try await getSession()

            try TestData.createFile(
                path: "\(testFolderPath)/child.txt",
                contents: "data"
            )

            let parentId = try await session.child(path: testFolderPath)
            let items = Mutex<[any NSFileProviderItemProtocol]>([])
            try await session.enumerateItems(for: parentId) { batch in
                items.withLock { $0.append(contentsOf: batch) }
            }

            let child = try #require(
                items.withLock { $0 }.first { $0.filename == "child.txt" }
            )
            #expect(child.parentItemIdentifier == parentId)
        }

        @Test func yieldedItemsHaveCorrectContentType() async throws {
            let session = try await getSession()

            try TestData.createFile(
                path: "\(testFolderPath)/a.txt",
                contents: "text"
            )
            try TestData.createFolder(path: "\(testFolderPath)/dir")

            let items = Mutex<[any NSFileProviderItemProtocol]>([])
            try await session.enumerateItems(
                for: session.child(path: testFolderPath)
            ) { batch in
                items.withLock { $0.append(contentsOf: batch) }
            }

            let snapshot = items.withLock { $0 }
            let file = try #require(snapshot.first { $0.filename == "a.txt" })
            let folder = try #require(snapshot.first { $0.filename == "dir" })
            #expect(file.contentType == .text)
            #expect(folder.contentType == .folder)
        }

        @Test func emptyDirectoryYieldsNoItems() async throws {
            let session = try await getSession()

            let emptyPath = "\(testFolderPath)/empty"
            try TestData.createFolder(path: emptyPath)

            let items = Mutex<[any NSFileProviderItemProtocol]>([])
            try await session.enumerateItems(
                for: session.child(path: emptyPath)
            ) { batch in
                items.withLock { $0.append(contentsOf: batch) }
            }

            #expect(items.withLock { $0 }.isEmpty)
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
