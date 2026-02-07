import Testing
import Foundation
@testable import SSHadowShared

private struct MockKeychain: KeychainProviding {
    var storage: [String: Data] = [:]

    func delete(_ key: String) {}

    func set(_ key: String, to data: Data) {}

    func set(_ key: String, to string: String) {}

    func get(_ key: String) -> Data? {storage[key]}

    func get(_ key: String) -> String? {
        guard let data = storage[key] else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func getPasswordKey(id: UUID) -> String {
        "password.\(id.uuidString)"
    }

    func getPrivateKeyPassphraseKey(id: UUID) -> String {
        "privateKeyPassphrase.\(id.uuidString)"
    }
}

@Suite(.serialized)
struct ConnectionTesterTests {
    @Test func testUnknownHost() async throws {
        let tester = DefaultConnectionTester()
        let id = UUID()

        var keychain = MockKeychain()
        keychain.storage[keychain.getPasswordKey(id: id)] = Data("mypass".utf8)
        Keychain.shared = keychain

        await #expect(throws: ConnectionTestError.unknownHost) {
            try await tester.test(
                config: ConnectionConfig(
                    id: id,
                    name: "test",
                    host: "unknown",
                    port: 22,
                    user: "user",
                    path: "/home/user",
                    authMethod: .password,
                )
            )
        }
    }

    @Test func testConnectionRefused() async throws {
        let tester = DefaultConnectionTester()
        let id = UUID()

        var keychain = MockKeychain()
        keychain.storage[keychain.getPasswordKey(id: id)] = Data("mypass".utf8)
        Keychain.shared = keychain

        await #expect(throws: ConnectionTestError.connectionRefused) {
            try await tester.test(
                config: ConnectionConfig(
                    id: id,
                    name: "test",
                    host: "localhost",
                    port: 2222,
                    user: "user",
                    path: "/home/user",
                    authMethod: .password,
                )
            )
        }
    }
}
