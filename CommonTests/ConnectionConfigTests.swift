import Testing
@testable import Common
import Foundation
import FileProvider

struct ConnectionConfigTests {
    @Test func testPathForWithEmptyConfigPath() {
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

    @Test func testPathForWithNonEmptyConfigPath() {
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
    
    @Test func testEmptyPathForRootContainerItem() {
        let configWithEmptyPath = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "",
            authMethod: .none
        )
        #expect(configWithEmptyPath.path(for: .rootContainer) == "")
    }
    
    @Test func testBasePathForRootContainerItem() {
        let configWithBasePath = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base",
            authMethod: .none
        )
        #expect(configWithBasePath.path(for: .rootContainer) == "base")
    }
    
    @Test func testEmptyPathForRegularItem() {
        let configWithEmptyPath = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "",
            authMethod: .none
        )
        let item = NSFileProviderItemIdentifier("folder/file.txt")
        #expect(configWithEmptyPath.path(for: item) == "folder/file.txt")
    }

    @Test func testBasePathForRegularItem() {
        let configWithBasePath = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base",
            authMethod: .none
        )
        let item = NSFileProviderItemIdentifier("folder/file.txt")
        #expect(configWithBasePath.path(for: item) == "base/folder/file.txt")
    }

    @Test func testAbsoluteURLForWithEmptyConfigPath() {
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

    @Test func testAbsoluteURLForWithNonEmptyConfigPath() {
         let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base",
            authMethod: .none
        )
        #expect(config.absoluteURL(for: "file.txt") == "user@host:base/file.txt")
    }
    
    @Test func testAbsoluteURLForWithEmptyConfigPathAndPort() {
        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 2222,
            user: "user",
            path: "",
            authMethod: .none
        )
        #expect(config.absoluteURL(for: "file.txt") == "user@host:2222:file.txt")
    }
}
