import Common
import Foundation
import SwiftData
import SwiftLibSSH
import Testing
import XPC

@testable import CoreKit

@Suite struct SSHClientExtensionTests {
    @Test func testThrowsUnknownHost() async throws {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "unknown",
            port: 22,
            user: "user",
            path: "/home/user",
            authMethod: .none,
        )

        await #expect(throws: ConnectionError.unknownHost) {
            try await SSHClient.connect(config: config)
        }
    }

    @Test func testThrowsConnectionRefused() async throws {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "localhost",
            port: 2223,
            user: "user",
            path: "/home/user",
            authMethod: .none,
        )

        await #expect(throws: ConnectionError.connectionRefused) {
            try await SSHClient.connect(config: config)
        }
    }
}

@Suite struct SFTPClientExtensionTests {
    private func connect(
        _ sandbox: TestSandbox
    ) async throws -> (SSHClient, SFTPClient) {
        let config = try sandbox.config
        return try await withConnectRetries {
            () async throws(ConnectionError) -> (SSHClient, SFTPClient) in
            try await SSHClient.connect(config: config)
        }
    }

    private func path(_ name: String, in sandbox: TestSandbox) -> String {
        sandbox.getUrl(for: name).path(percentEncoded: false)
    }

    @Test func makeDirectoryOverFolderThrowsAlreadyExists() async throws {
        let sandbox = TestSandbox()
        _ = try sandbox.createFolder(at: "dir")
        let (_, sftp) = try await connect(sandbox)

        await #expect {
            try await sftp.makeDirectory(
                at: path("dir", in: sandbox),
                mode: 0o755
            )
        } throws: { ($0 as? SSHError)?.sftpError == .fileAlreadyExists }
    }

    @Test func makeDirectoryOverFileThrowsAlreadyExists() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "file")
        let (_, sftp) = try await connect(sandbox)

        await #expect {
            try await sftp.makeDirectory(
                at: path("file", in: sandbox),
                mode: 0o755
            )
        } throws: { ($0 as? SSHError)?.sftpError == .fileAlreadyExists }
    }

    @Test func makeDirectoryIfExistsSucceedOverFolderSucceeds() async throws {
        let sandbox = TestSandbox()
        _ = try sandbox.createFolder(at: "dir")
        let (_, sftp) = try await connect(sandbox)

        try await sftp.makeDirectory(
            at: path("dir", in: sandbox),
            mode: 0o755,
            ifExists: .succeed
        )
    }

    @Test func makeDirectoryIfExistsSucceedOverFileThrowsAlreadyExists()
        async throws
    {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "file")
        let (_, sftp) = try await connect(sandbox)

        await #expect {
            try await sftp.makeDirectory(
                at: path("file", in: sandbox),
                mode: 0o755,
                ifExists: .succeed
            )
        } throws: { ($0 as? SSHError)?.sftpError == .fileAlreadyExists }
    }

    @Test func makeDirectoryIfExistsSucceedOverSymlinkThrowsAlreadyExists()
        async throws
    {
        let sandbox = TestSandbox()
        _ = try sandbox.createFolder(at: "target-dir")
        try sandbox.createSymlink(at: "link-dir", target: "target-dir")
        let (_, sftp) = try await connect(sandbox)

        await #expect {
            try await sftp.makeDirectory(
                at: path("link-dir", in: sandbox),
                mode: 0o755,
                ifExists: .succeed
            )
        } throws: { ($0 as? SSHError)?.sftpError == .fileAlreadyExists }
    }

    @Test func makeDirectoryWithMissingParentIsNotACollision() async throws {
        let sandbox = TestSandbox()
        let (_, sftp) = try await connect(sandbox)

        await #expect {
            try await sftp.makeDirectory(
                at: path("missing/dir", in: sandbox),
                mode: 0o755
            )
        } throws: { ($0 as? SSHError)?.sftpError != .fileAlreadyExists }
    }

    @Test func makeSymlinkOverFileThrowsAlreadyExists() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "file")
        let (_, sftp) = try await connect(sandbox)

        await #expect {
            try await sftp.makeSymlink(
                to: "target",
                at: path("file", in: sandbox)
            )
        } throws: { ($0 as? SSHError)?.sftpError == .fileAlreadyExists }
    }

    @Test func writeFileOverFolderThrowsAlreadyExists() async throws {
        let sandbox = TestSandbox()
        _ = try sandbox.createFolder(at: "dir")
        let (_, sftp) = try await connect(sandbox)

        await #expect {
            try await sftp.writeFile(
                at: path("dir", in: sandbox),
                mode: 0o644
            ) {
                try await $0.write(data: Data("data".utf8))
            }
        } throws: { ($0 as? SSHError)?.sftpError == .fileAlreadyExists }
    }

    @Test func writeFileOverFileOverwrites() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "file", contents: "old contents")
        let (_, sftp) = try await connect(sandbox)

        try await sftp.writeFile(at: path("file", in: sandbox), mode: 0o644) {
            try await $0.write(data: Data("new".utf8))
        }

        #expect(try sandbox.contents(of: "file") == "new")
    }

    @Test func attributesIfExistsReturnsFileAttributes() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "file", contents: "data")
        let (_, sftp) = try await connect(sandbox)

        let attrs = try await sftp.attributesIfExists(
            at: path("file", in: sandbox)
        )
        #expect(attrs?.type == .regular)
        #expect(attrs?.size == 4)
    }

    @Test func attributesIfExistsReturnsFolderAttributes() async throws {
        let sandbox = TestSandbox()
        _ = try sandbox.createFolder(at: "dir")
        let (_, sftp) = try await connect(sandbox)

        let attrs = try await sftp.attributesIfExists(
            at: path("dir", in: sandbox)
        )
        #expect(attrs?.type == .directory)
    }

    @Test func attributesIfExistsDoesNotFollowSymlinks() async throws {
        let sandbox = TestSandbox()
        _ = try sandbox.createFolder(at: "target-dir")
        try sandbox.createSymlink(at: "link-dir", target: "target-dir")
        let (_, sftp) = try await connect(sandbox)

        let attrs = try await sftp.attributesIfExists(
            at: path("link-dir", in: sandbox)
        )
        #expect(attrs?.type == .symlink)
    }

    @Test func attributesIfExistsReturnsDanglingSymlink() async throws {
        let sandbox = TestSandbox()
        try sandbox.createSymlink(at: "link", target: "missing")
        let (_, sftp) = try await connect(sandbox)

        let attrs = try await sftp.attributesIfExists(
            at: path("link", in: sandbox)
        )
        #expect(attrs?.type == .symlink)
    }

    @Test func attributesIfExistsReturnsNilForMissingPath() async throws {
        let sandbox = TestSandbox()
        let (_, sftp) = try await connect(sandbox)

        let attrs = try await sftp.attributesIfExists(
            at: path("missing", in: sandbox)
        )
        #expect(attrs == nil)
    }

    @Test func attributesIfExistsReturnsNilForMissingParent() async throws {
        let sandbox = TestSandbox()
        let (_, sftp) = try await connect(sandbox)

        let attrs = try await sftp.attributesIfExists(
            at: path("missing/file", in: sandbox)
        )
        #expect(attrs == nil)
    }

    @Test func isDirectoryIsTrueForFolder() async throws {
        let sandbox = TestSandbox()
        _ = try sandbox.createFolder(at: "dir")
        let (_, sftp) = try await connect(sandbox)

        #expect(try await sftp.isDirectory(at: path("dir", in: sandbox)))
    }

    @Test func isDirectoryIsFalseForFile() async throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "file")
        let (_, sftp) = try await connect(sandbox)

        #expect(try await !sftp.isDirectory(at: path("file", in: sandbox)))
    }

    @Test func isDirectoryIsFalseForSymlinkToFolder() async throws {
        let sandbox = TestSandbox()
        _ = try sandbox.createFolder(at: "target-dir")
        try sandbox.createSymlink(at: "link-dir", target: "target-dir")
        let (_, sftp) = try await connect(sandbox)

        #expect(
            try await !sftp.isDirectory(at: path("link-dir", in: sandbox))
        )
    }

    @Test func isDirectoryIsFalseForMissingPath() async throws {
        let sandbox = TestSandbox()
        let (_, sftp) = try await connect(sandbox)

        #expect(try await !sftp.isDirectory(at: path("missing", in: sandbox)))
    }
}
