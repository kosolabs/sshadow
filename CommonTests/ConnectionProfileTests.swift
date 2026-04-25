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

    @Test func testAbsoluteUrlWithEmptyConfigPath() {
        let config = ConnectionProfile(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "",
            authMethod: .password
        )
        #expect(config.absoluteUrl(for: "file.txt") == "user@host:file.txt")
    }

    @Test func testAbsoluteUrlWithNonEmptyConfigPath() {
        let config = ConnectionProfile(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base",
            authMethod: .password
        )
        #expect(
            config.absoluteUrl(for: "file.txt") == "user@host:base/file.txt"
        )
    }

    @Test func testAbsoluteUrlWithSlashSuffixConfigPath() {
        let config = ConnectionProfile(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base/",
            authMethod: .password
        )
        #expect(
            config.absoluteUrl(for: "file.txt") == "user@host:base/file.txt"
        )
    }

    @Test func testAbsoluteUrlWithSlashPrefixConfigPath() {
        let config = ConnectionProfile(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "/base",
            authMethod: .password
        )
        #expect(
            config.absoluteUrl(for: "file.txt") == "user@host:/base/file.txt"
        )
    }

    @Test func testAbsoluteUrlWithEmptyConfigPathAndPort() {
        let config = ConnectionProfile(
            id: UUID(),
            name: "test",
            host: "host",
            port: 2222,
            user: "user",
            path: "",
            authMethod: .password
        )
        #expect(
            config.absoluteUrl(for: "file.txt") == "user@host:2222:file.txt"
        )
    }
}
