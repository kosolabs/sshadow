import Extension
import FileProvider
import Foundation
import Testing

@testable import Common

struct ConnectionConfigTests {
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

    @Test func testPathForTrashContainerItem() {
        let configWithEmptyPath = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "host",
            port: 22,
            user: "user",
            path: "base",
            authMethod: .none
        )
        #expect(
            configWithEmptyPath.path(for: .trashContainer) == "base/.Trashes"
        )
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
}
