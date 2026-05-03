import Foundation
import Testing

@testable import Common

struct ConnectionProfileTests {
    @Test func testPathWithEmptyConfigPath() {
        let config = ConnectionProfile(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "",
            authMethod: .password
        )

        #expect(config.path(for: "file.txt") == "file.txt")
    }

    @Test func testPathWithNonEmptyConfigPath() {
        let config = ConnectionProfile(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base",
            authMethod: .password
        )

        #expect(config.path(for: "file.txt") == "base/file.txt")
    }

    @Test func testPathWithEmptySubpath() {
        let config = ConnectionProfile(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base",
            authMethod: .password
        )

        #expect(config.path(for: "") == "base")
    }

    @Test func testPathWithRootInConfigPath() {
        let config = ConnectionProfile(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "/",
            authMethod: .password
        )

        #expect(config.path(for: "file.txt") == "/file.txt")
    }

    @Test func testPathWithSlashSuffixInConfigPath() {
        let config = ConnectionProfile(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base/",
            authMethod: .password
        )

        #expect(config.path(for: "file.txt") == "base/file.txt")
    }

    @Test func testPathWithSlashPrefixInConfigPath() {
        let config = ConnectionProfile(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "/base",
            authMethod: .password
        )

        #expect(config.path(for: "file.txt") == "/base/file.txt")
    }
}
