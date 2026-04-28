import FileProvider
import Foundation
import SwiftLibSSH
import Testing

@testable import Common

private func getAgentClient() async throws -> AgentClient {
    try await TestData.initAppDB()
    return TestData.getAgentClient()
}

struct AgentClientTests {
    let testFolderPath = "agent-client"
    let testFolderURL: URL

    init() throws {
        testFolderURL = try TestData.createFolder(path: testFolderPath)
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
    
    @Test func infoForFileSucceeds() async throws {
        let agent = try await getAgentClient()

        let path = "\(testFolderPath)/info-file.txt"
        let contents = "Hello, World!"
        try TestData.createFile(path: path, contents: contents)

        let itemId = try await agent.child(path: path)
        let info = try await agent.info(for: itemId)

        #expect(info.name == "info-file.txt")
        #expect(!info.isDirectory)
        #expect(info.size == UInt64(contents.utf8.count))
    }

    @Test func infoForDirectorySucceeds() async throws {
        let agent = try await getAgentClient()

        let path = "\(testFolderPath)/info-dir"
        try TestData.createFolder(path: path)

        let itemId = try await agent.child(path: path)
        let info = try await agent.info(for: itemId)

        #expect(info.name == "info-dir")
        #expect(info.isDirectory)
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
        #expect(!fileEntry.isDirectory)

        let folderEntry = try #require(
            entries.first { $0.name == "subfolder" }
        )
        #expect(folderEntry.isDirectory)
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
        let info = try await agent.info(for: itemId)

        #expect(info.permissions & 0o777 == 0o644)
    }
    
    @Test func createDirectorySucceeds() async throws {
        let agent = try await getAgentClient()

        let path = "\(testFolderPath)/new-dir"
        let itemId = try await agent.child(path: path)

        try await agent.createDirectory(for: itemId, mode: 0o755)
        let info = try await agent.info(for: itemId)

        #expect(info.isDirectory)
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
}

func isNoSuchItemError(_ error: any Error) -> Bool {
    (error as NSError).code == NSFileProviderError.noSuchItem.rawValue
        && (error as NSError).domain == NSFileProviderErrorDomain
}
