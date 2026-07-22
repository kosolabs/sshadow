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

        await #expect(throws: SSHClient.TestError.unknownHost) {
            try await SSHClient.test(config: config)
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

        await #expect(throws: SSHClient.TestError.connectionRefused) {
            try await SSHClient.test(config: config)
        }
    }
}
