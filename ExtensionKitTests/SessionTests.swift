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
