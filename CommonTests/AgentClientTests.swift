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

    @Test func attributesSucceeds() async throws {
        let agent = try await getAgentClient()

        let path = "\(testFolderPath)/file.txt"
        let contents = "Hello, World!"
        try TestData.createFile(path: path, contents: contents)

        let attrs = try await agent.attributes(
            for: agent.child(path: path)
        )

        #expect(attrs.type == .regular)
        #expect(attrs.size == UInt64(contents.utf8.count))
    }

    @Test func attributesThrowsExpectedError() async throws {
        let agent = try await getAgentClient()

        await #expect {
            try await agent.attributes(
                for: agent.child(
                    path: "\(testFolderPath)/missing.txt",
                    ifNotExists: .fail
                )
            )
        } throws: { error in isNoSuchItemError(error) }
    }
}

func isNoSuchItemError(_ error: any Error) -> Bool {
    (error as NSError).code == NSFileProviderError.noSuchItem.rawValue
        && (error as NSError).domain == NSFileProviderErrorDomain
}
