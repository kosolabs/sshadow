import Foundation
import SwiftLibSSH
import Testing

@testable import SSHadowShared

struct ConnectionTesterTests {
    @Test func testConnectionSucceeds() async throws {
        let config = try ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "localhost",
            port: 2248,
            user: NSUserName(),
            path: "Public",
            authMethod: .privateKey(
                base64PrivateKey: Data(
                    contentsOf: URL(filePath: "/tmp/id_ed25519")
                ).decoded(as: .utf8),
                passphrase: nil
            ),
        )

        try await SSHClient.withSession(config: config) {
            _,
            sftpClient in
            try await sftpClient.withDirectory(atPath: "media") { dir in
                for try await attr in dir {
                    if let name = attr.name {
                        print("\(name)")
                    }
                }
            }
        }
    }

    @Test func testUnknownHost() async throws {
        let tester = DefaultConnectionTester()

        await #expect(throws: ConnectionTestError.unknownHost) {
            try await tester.test(
                config: ConnectionConfig(
                    id: UUID(),
                    name: "test",
                    host: "unknown",
                    port: 22,
                    user: "user",
                    path: "/home/user",
                    authMethod: .none,
                )
            )
        }
    }

    @Test func testConnectionRefused() async throws {
        let tester = DefaultConnectionTester()

        await #expect(throws: ConnectionTestError.connectionRefused) {
            try await tester.test(
                config: ConnectionConfig(
                    id: UUID(),
                    name: "test",
                    host: "localhost",
                    port: 2223,
                    user: "user",
                    path: "/home/user",
                    authMethod: .none,
                )
            )
        }
    }
}
