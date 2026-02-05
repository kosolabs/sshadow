import Testing
import Foundation
@testable import SSHadowShared

struct ConnectionTesterTests {
    @Test func testUnknownHost() async throws {
        let tester = DefaultConnectionTester()
        
        await #expect(throws: ConnectionTestError.unknownHost) {
            try await tester.test(
                config: ConnectionConfig(
                    id: UUID(),
                    name: "test",
                    enabled: true,
                    host: "unknown",
                    port: 22,
                    user: "user",
                    path: "/home/user",
                    authMethod: .password("pass")
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
                    enabled: true,
                    host: "localhost",
                    port: 2222,
                    user: "user",
                    path: "/home/user",
                    authMethod: .password("pass")
                )
            )
        }
    }
    
    @Test func testTimeout() async throws {
        let tester = DefaultConnectionTester()
        
        await #expect(throws: ConnectionTestError.timeout) {
            try await tester.test(
                config: ConnectionConfig(
                    id: UUID(),
                    name: "test",
                    enabled: true,
                    host: "192.0.2.1",
                    port: 22,
                    user: "user",
                    path: "/home/user",
                    authMethod: .password("pass")
                )
            )
        }
    }
}
