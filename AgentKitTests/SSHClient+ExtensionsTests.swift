import Common
import Foundation
import SwiftLibSSH
import Testing

@testable import AgentKit

struct ConnectionTesterTests {
    @Test func testConnectionSucceeds() async throws {
        let sandbox = TestSandbox()
        let config = try sandbox.getConnectionConfig()

        try await SSHClient.test(config: config)
    }

    @Test func testUnknownHost() async throws {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "unknown",
            port: 22,
            user: "user",
            path: "/home/user",
            authMethod: .none,
        )

        await #expect(throws: InitDomainError.unknownHost) {
            try await SSHClient.test(config: config)
        }
    }

    @Test func testConnectionRefused() async throws {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "localhost",
            port: 2223,
            user: "user",
            path: "/home/user",
            authMethod: .none,
        )

        await #expect(throws: InitDomainError.connectionRefused) {
            try await SSHClient.test(config: config)
        }
    }
}
