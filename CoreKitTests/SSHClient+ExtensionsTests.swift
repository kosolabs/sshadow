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
