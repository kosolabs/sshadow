import FileProvider
import Foundation
import Testing

@testable import Common

struct CoreClientTests {
    @Test func nameAndChildAndParentSucceed() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(
            at: "folder/file.txt",
            contents: "Hello, World!"
        )
        let client = try await sandbox.client
        let folderId = try await client.child(name: "folder")
        let nestedFile = try await client.child(of: folderId, name: "file.txt")
        let nestedFileName = try await client.name(of: nestedFile)
        #expect(nestedFileName == "file.txt")

        let parentOfFileId = try await client.parent(of: nestedFile)
        #expect(parentOfFileId == folderId)
    }

    @Test func itemForFileSucceeds() async throws {
        let sandbox = TestSandbox()
        let contents = "Hello, World!"
        try sandbox.createFile(at: "file.txt", contents: contents)
        let client = try await sandbox.client
        let itemId = try await client.child(name: "file.txt")
        let item = try await client.item(for: itemId)

        #expect(item.name == "file.txt")
        #expect(item.kind == .file)
        #expect(item.size == UInt64(contents.utf8.count))
    }

    @Test func itemForFolderSucceeds() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFolder(at: "folder")
        let client = try await sandbox.client
        let itemId = try await client.child(name: "folder")
        let item = try await client.item(for: itemId)

        #expect(item.name == "folder")
        #expect(item.kind == .folder)
    }

    @Test func itemForSymlinkSucceeds() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "target.txt", contents: "Hello, World!")
        try sandbox.createSymlink(at: "symlink.txt", target: "target.txt")
        let client = try await sandbox.client
        let itemId = try await client.child(name: "symlink.txt")
        let item = try await client.item(for: itemId)

        #expect(item.name == "symlink.txt")
        #expect(item.kind == .symlink(target: "target.txt"))
    }

    @Test func listSucceeds() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "file.txt")
        try sandbox.createFolder(at: "folder")
        try sandbox.createSymlink(at: "symlink.txt", target: "file.txt")
        let client = try await sandbox.client
        let entries = try await client.list(for: .rootContainer)

        let file = try #require(entries.first { $0.name == "file.txt" })
        #expect(file.kind == .file)

        let folder = try #require(entries.first { $0.name == "folder" })
        #expect(folder.kind == .folder)

        let symlink = try #require(entries.first { $0.name == "symlink.txt" })
        #expect(symlink.kind == .symlink(target: "file.txt"))
    }

    @Test func listEmptyDirectorySucceeds() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFolder(at: "empty-dir")
        let client = try await sandbox.client
        let dirId = try await client.child(name: "empty-dir")
        let entries = try await client.list(for: dirId)

        #expect(entries.isEmpty)
    }

    @Test func setAttributesSucceeds() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "set-attrs.txt")
        let client = try await sandbox.client
        let itemId = try await client.child(name: "set-attrs.txt")
        try await client.setAttributes(for: itemId, flags: .rw)
        let item = try await client.item(for: itemId)

        #expect(item.flags == .rw)
    }

    @Test func createSymlinkSucceeds() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "target.txt")
        let client = try await sandbox.client
        let item = try await client.createSymlink(
            parentId: .rootContainer,
            name: "symlink.txt",
            target: "target.txt"
        )

        #expect(item.name == "symlink.txt")
        #expect(item.kind == .symlink(target: "target.txt"))
    }

    @Test func createDirectorySucceeds() async throws {
        let sandbox = TestSandbox()
        let client = try await sandbox.client
        let item = try await client.createDirectory(
            parentId: .rootContainer,
            name: "new-dir",
            flags: .all
        )

        #expect(item.name == "new-dir")
        #expect(item.kind == .folder)
    }

    @Test func moveSucceeds() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "src/old.txt")
        try sandbox.createFolder(at: "dest")
        let client = try await sandbox.client
        let srcId = try await client.child(name: "src")
        let itemId = try await client.child(of: srcId, name: "old.txt")
        let destId = try await client.child(name: "dest")

        try await client.move(itemId, toParent: destId, name: "new.txt")

        let name = try await client.name(of: itemId)
        #expect(name == "new.txt")
        let parentId = try await client.parent(of: itemId)
        #expect(parentId == destId)
    }

    @Test func removeFileSucceeds() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "file.txt")
        let client = try await sandbox.client
        let itemId = try await client.child(name: "file.txt")
        try await client.removeFile(for: itemId)

        #expect(!sandbox.exists(at: "file.txt"))
    }

    @Test func removeDirectorySucceeds() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFolder(at: "folder")
        let client = try await sandbox.client
        let itemId = try await client.child(name: "folder")
        try await client.removeDirectory(for: itemId)

        #expect(!sandbox.exists(at: "folder"))
    }

    @Test func limitsSucceeds() async throws {
        let sandbox = TestSandbox()
        let client = try await sandbox.client
        let limits = try await client.limits()

        #expect(limits.maxReadLength > 0)
        #expect(limits.maxWriteLength > 0)
    }

    @Test func uploadSucceeds() async throws {
        let sandbox = TestSandbox()
        let client = try await sandbox.client
        let contents = "uploaded content"
        let localFile = sandbox.shared.appending(path: UUID().uuidString)
        try contents.write(to: localFile, atomically: true, encoding: .utf8)

        let item = try await client.upload(
            parentId: .rootContainer,
            name: "upload.txt",
            file: localFile,
            flags: .rw,
            progress: Progress()
        )

        #expect(item.name == "upload.txt")
        #expect(item.size == UInt64(contents.utf8.count))
    }

    @Test func downloadSucceeds() async throws {
        let sandbox = TestSandbox()
        let contents = "download me"
        try sandbox.createFile(at: "download.txt", contents: contents)
        let client = try await sandbox.client
        let itemId = try await client.child(name: "download.txt")
        let (url, item) = try await client.download(
            itemId: itemId,
            progress: Progress()
        )

        let downloaded = try String(contentsOf: url, encoding: .utf8)
        #expect(downloaded == contents)
        #expect(item.name == "download.txt")
        #expect(item.size == UInt64(contents.utf8.count))
    }
}

func isNoSuchItemError(_ error: any Error) -> Bool {
    (error as NSError).code == NSFileProviderError.noSuchItem.rawValue
        && (error as NSError).domain == NSFileProviderErrorDomain
}
