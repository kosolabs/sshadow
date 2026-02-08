import Foundation
import Testing

@testable import SSHadowShared

struct ConnectionTesterTests {
    @Test func testUnknownHost() async throws {
        let tester = DefaultConnectionTester()

        await #expect(throws: ConnectionTestError.unknownHost) {
            try await tester.test(
                config: ConnectionConfig(
                    id: UUID(),
                    name: "test",
                    host: "unknown",
                    port: 22,
                    user: "user",
                    path: "/home/user",
                    authMethod: .none,
                )
            )
        }
    }

    @Test func testConnectionRefused() async throws {
        let tester = DefaultConnectionTester()
        
        await #expect(throws: ConnectionTestError.connectionRefused) {
            try await tester.test(
                config: ConnectionConfig(
                    id: UUID(),
                    name: "test",
                    host: "localhost",
                    port: 2222,
                    user: "user",
                    path: "/home/user",
                    authMethod: .none,
                )
            )
        }
    }
}
