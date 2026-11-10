import Foundation
import Testing

@testable import CoreKit

struct ConnectionConfigTests {
    @Test func testPathWithEmptyConfigPath() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "",
            authMethod: .none,
            ignoreFilenames: [],
            hostKey: unrelatedHostKey,
            poll: nil,
            connectTimeout: .seconds(60),
            maxReconnectDelay: .seconds(60)
        )

        #expect(config.path(for: "file.txt") == "file.txt")
    }

    @Test func testPathWithEmptyConfigPathAndEmptySubpath() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "",
            authMethod: .none,
            ignoreFilenames: [],
            hostKey: unrelatedHostKey,
            poll: nil,
            connectTimeout: .seconds(60),
            maxReconnectDelay: .seconds(60)
        )

        #expect(config.path(for: "") == ".")
    }

    @Test func testPathWithNonEmptyConfigPath() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base",
            authMethod: .none,
            ignoreFilenames: [],
            hostKey: unrelatedHostKey,
            poll: nil,
            connectTimeout: .seconds(60),
            maxReconnectDelay: .seconds(60)
        )

        #expect(config.path(for: "file.txt") == "base/file.txt")
    }

    @Test func testPathWithEmptySubpath() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base",
            authMethod: .none,
            ignoreFilenames: [],
            hostKey: unrelatedHostKey,
            poll: nil,
            connectTimeout: .seconds(60),
            maxReconnectDelay: .seconds(60)
        )

        #expect(config.path(for: "") == "base")
    }

    @Test func testPathWithSlashSuffixInConfigPath() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base/",
            authMethod: .none,
            ignoreFilenames: [],
            hostKey: unrelatedHostKey,
            poll: nil,
            connectTimeout: .seconds(60),
            maxReconnectDelay: .seconds(60)
        )

        #expect(config.path(for: "file.txt") == "base/file.txt")
    }

    @Test func testPathWithSlashPrefixInConfigPath() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "/base",
            authMethod: .none,
            ignoreFilenames: [],
            hostKey: unrelatedHostKey,
            poll: nil,
            connectTimeout: .seconds(60),
            maxReconnectDelay: .seconds(60)
        )

        #expect(config.path(for: "file.txt") == "/base/file.txt")
    }
}
