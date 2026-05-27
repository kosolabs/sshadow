import FileProvider
import Foundation
import SwiftLibSSH
import Testing

@testable import Common

private func getAgentClient() async throws -> AgentClient {
    try await TestData.getAgentClient()
}

struct AgentClientTests {
    let testFolderPath = "agent-client"
    let testFolderUrl: URL

    init() throws {
        testFolderUrl = try TestData.createFolder(path: testFolderPath)
    }

    @Test func nameAndChildAndParentSucceed() async throws {
        let agent = try await getAgentClient()

        let nestedFile = try await agent.child(path: "folder/file")
        let nestedFileName = try await agent.name(of: nestedFile)
        #expect(nestedFileName == "file")

        let parentOfFileId = try await agent.parent(of: nestedFile)
        let childOfRootId = try await agent.child(path: "folder")
        #expect(parentOfFileId == childOfRootId)
    }

    @Test func pathForItemSucceeds() async throws {
        let agent = try await getAgentClient()
        let itemId = try await agent.child(path: "folder/file.txt")
        let path = try await agent.path(for: itemId)
        #expect(path.hasSuffix("/folder/file.txt"))
    }

    @Test func pathForChildSucceeds() async throws {
        let agent = try await getAgentClient()
        let parentId = try await agent.child(path: "folder")
        let path = try await agent.path(for: "file.txt", parentId: parentId)
        #expect(path.hasSuffix("/folder/file.txt"))
    }

    @Test func itemForFileSucceeds() async throws {
        let agent = try await getAgentClient()

        let path = "\(testFolderPath)/item-file.txt"
        let contents = "Hello, World!"
        try TestData.createFile(path: path, contents: contents)

        let itemId = try await agent.child(path: path)
        let item = try await agent.item(for: itemId)

        #expect(item.name == "item-file.txt")
        #expect(item.kind == .file)
        #expect(item.size == UInt64(contents.utf8.count))
    }

    @Test func itemForFolderSucceeds() async throws {
        let agent = try await getAgentClient()

        let path = "\(testFolderPath)/item-dir"
        try TestData.createFolder(path: path)

        let itemId = try await agent.child(path: path)
        let item = try await agent.item(for: itemId)

        #expect(item.name == "item-dir")
        #expect(item.kind == .folder)
    }

    @Test func itemForSymlinkSucceeds() async throws {
        let agent = try await getAgentClient()

        let target = "\(testFolderPath)/item-symlink-target.txt"
        let contents = "Hello, World!"
        try TestData.createFile(path: target, contents: contents)
        let symlink = "\(testFolderPath)/item-symlink-link.txt"
        try TestData.createSymlink(path: symlink, target: target)

        let itemId = try await agent.child(path: symlink)
        let item = try await agent.item(for: itemId)

        #expect(item.name == "item-symlink-link.txt")
        #expect(item.kind == .symlink(target: target))
    }

    @Test func listSucceeds() async throws {
        let agent = try await getAgentClient()

        let dirPath = "\(testFolderPath)/enum-dir"
        try TestData.createFile(
            path: "\(dirPath)/file.txt",
            contents: "hello"
        )
        try TestData.createFolder(path: "\(dirPath)/subfolder")

        let dirId = try await agent.child(path: dirPath)
        let entries = try await agent.list(for: dirId)

        let names = Set(entries.map(\.name))
        #expect(names.contains("file.txt"))
        #expect(names.contains("subfolder"))

        let fileEntry = try #require(entries.first { $0.name == "file.txt" })
        #expect(fileEntry.kind == .file)

        let folderEntry = try #require(
            entries.first { $0.name == "subfolder" }
        )
        #expect(folderEntry.kind == .folder)
    }

    @Test func listEmptyDirectorySucceeds() async throws {
        let agent = try await getAgentClient()

        let dirPath = "\(testFolderPath)/empty-dir"
        try TestData.createFolder(path: dirPath)

        let dirId = try await agent.child(path: dirPath)
        let entries = try await agent.list(for: dirId)

        #expect(entries.isEmpty)
    }

    @Test func setAttributesSucceeds() async throws {
        let agent = try await getAgentClient()

        let path = "\(testFolderPath)/set-attrs.txt"
        try TestData.createFile(path: path, contents: "test")
        let itemId = try await agent.child(path: path)

        try await agent.setAttributes(for: itemId, permissions: 0o644)
        let item = try await agent.item(for: itemId)
        
        let permissions = try #require(item.permissions)
        #expect(permissions & 0o777 == 0o644)
    }

    @Test func createSymlinkSucceeds() async throws {
        let agent = try await getAgentClient()

        let target = "\(testFolderPath)/symlink-target.txt"
        try TestData.createFile(path: target, contents: "hello")

        let parentId = try await agent.child(path: testFolderPath)

        let item = try await agent.createSymlink(
            parentId: parentId,
            name: "symlink-link.txt",
            target: target
        )

        #expect(item.name == "symlink-link.txt")
        #expect(item.kind == .symlink(target: target))
    }

    @Test func createDirectorySucceeds() async throws {
        let agent = try await getAgentClient()

        let parentId = try await agent.child(path: testFolderPath)

        let item = try await agent.createDirectory(
            parentId: parentId,
            name: "new-dir",
            mode: 0o755
        )

        #expect(item.name == "new-dir")
        #expect(item.kind == .folder)
    }

    @Test func moveSucceeds() async throws {
        let agent = try await getAgentClient()

        let path = "\(testFolderPath)/move-me.txt"
        try TestData.createFile(path: path, contents: "hello")
        let itemId = try await agent.child(path: path)
        let parentId = try await agent.child(path: testFolderPath)

        try await agent.move(
            itemId,
            toParent: parentId,
            name: "moved.txt"
        )

        let name = try await agent.name(of: itemId)
        #expect(name == "moved.txt")
    }

    @Test func removeFileSucceeds() async throws {
        let agent = try await getAgentClient()

        let path = "\(testFolderPath)/rm-file.txt"
        try TestData.createFile(path: path, contents: "bye")
        let itemId = try await agent.child(path: path)

        try await agent.removeFile(for: itemId)
        let exists = try await agent.exists(for: itemId)

        #expect(exists == false)
    }

    @Test func removeDirectorySucceeds() async throws {
        let agent = try await getAgentClient()

        let path = "\(testFolderPath)/rm-dir"
        try TestData.createFolder(path: path)
        let itemId = try await agent.child(path: path)

        try await agent.removeDirectory(for: itemId)
        let exists = try await agent.exists(for: itemId)

        #expect(exists == false)
    }

    @Test func limitsSucceeds() async throws {
        let agent = try await getAgentClient()

        let limits = try await agent.limits()

        #expect(limits.maxReadLength > 0)
        #expect(limits.maxWriteLength > 0)
    }

    @Test func uploadSucceeds() async throws {
        let agent = try await getAgentClient()

        let parentId = try await agent.child(path: testFolderPath)
        let contents = "uploaded content"
        let localFile = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try contents.write(to: localFile, atomically: true, encoding: .utf8)

        let item = try await agent.upload(
            parentId: parentId,
            name: "upload.txt",
            file: localFile,
            mode: 0o644,
            progress: Progress()
        )

        #expect(item.name == "upload.txt")
        #expect(item.size == UInt64(contents.utf8.count))
    }

    @Test func downloadSucceeds() async throws {
        let agent = try await getAgentClient()

        let path = "\(testFolderPath)/download.txt"
        let contents = "download me"
        try TestData.createFile(path: path, contents: contents)
        let itemId = try await agent.child(path: path)

        let (url, fileInfo) = try await agent.download(
            itemId: itemId,
            progress: Progress()
        )

        let downloaded = try String(contentsOf: url, encoding: .utf8)
        #expect(downloaded == contents)
        #expect(fileInfo.name == "download.txt")
        #expect(fileInfo.size == UInt64(contents.utf8.count))
    }
}

func isNoSuchItemError(_ error: any Error) -> Bool {
    (error as NSError).code == NSFileProviderError.noSuchItem.rawValue
        && (error as NSError).domain == NSFileProviderErrorDomain
}
