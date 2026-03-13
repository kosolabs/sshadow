import Foundation
import Testing

@testable import Common

struct ConnectionConfigTests {
    @Test func testPathWithEmptyConfigPath() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "",
            authMethod: .none
        )

        #expect(config.path(for: "file.txt") == "file.txt")
    }

    @Test func testPathWithNonEmptyConfigPath() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base",
            authMethod: .none
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
            authMethod: .none
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
            authMethod: .none
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
            authMethod: .none
        )

        #expect(config.path(for: "file.txt") == "/base/file.txt")
    }

    @Test func testAbsoluteURLWithEmptyConfigPath() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "",
            authMethod: .none
        )
        #expect(config.absoluteURL(for: "file.txt") == "user@host:file.txt")
    }

    @Test func testAbsoluteURLWithNonEmptyConfigPath() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base",
            authMethod: .none
        )
        #expect(
            config.absoluteURL(for: "file.txt") == "user@host:base/file.txt"
        )
    }

    @Test func testAbsoluteURLWithSlashSuffixConfigPath() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base/",
            authMethod: .none
        )
        #expect(
            config.absoluteURL(for: "file.txt") == "user@host:base/file.txt"
        )
    }

    @Test func testAbsoluteURLWithSlashPrefixConfigPath() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "/base",
            authMethod: .none
        )
        #expect(
            config.absoluteURL(for: "file.txt") == "user@host:/base/file.txt"
        )
    }

    @Test func testAbsoluteURLWithEmptyConfigPathAndPort() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 2222,
            user: "user",
            path: "",
            authMethod: .none
        )
        #expect(
            config.absoluteURL(for: "file.txt") == "user@host:2222:file.txt"
        )
    }
}
