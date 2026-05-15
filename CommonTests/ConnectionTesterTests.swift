import Foundation
import SwiftLibSSH
import Testing

@testable import Common

struct ConnectionTesterTests {
    @Test func testConnectionSucceeds() async throws {
        let config = try TestData.getConnectionConfig()
        try await SSHClient.withSession(config: config) { _, sftp in
            try await sftp.withDirectory(at: config.path) { dir in
                for try await _ in dir {}
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
