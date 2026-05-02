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
    struct WithFileTests {
        let testFolderPath = "session-with-file"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func withFileReadSucceeds() async throws {
            let session = try await getSession()
            let agent = session.agent

            let path = "\(testFolderPath)/read-file.txt"
            let contents = "Hello, World!"
            try TestData.createFile(path: path, contents: contents)

            let data = try await session.withFile(
                for: agent.child(path: path),
                accessType: .readOnly
            ) { file in
                try await file.read()
            }

            #expect(String(data: data, encoding: .utf8) == contents)
        }

        @Test func withFileMissingFileThrowsNoSuchItem() async throws {
            let session = try await getSession()
            let agent = session.agent

            await #expect {
                try await session.withFile(
                    for: agent.child(
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
