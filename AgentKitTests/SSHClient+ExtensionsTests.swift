import AgentKit
import Common
import Foundation
import SwiftData
import Testing
import XPC

@Suite struct AgentInitDomainTests {
    private static func makeBareAgent() throws -> (AgentClient, XPCListener) {
        let appDb = try AppDB.open(
            config: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let shared = FileManager.default.temporaryDirectory
        let listener = Agent.testListener(
            appDb: appDb,
            domainDbConfig: ModelConfiguration(isStoredInMemoryOnly: true),
            sharedUrl: shared
        )
        let session = try XPCSession(endpoint: listener.endpoint)
        let agent = AgentClient(
            domainId: UUID(),
            session: session,
            sharedUrl: shared
        )
        return (agent, listener)
    }

    @Test func initDomainSucceeds() async throws {
        let sandbox = TestSandbox()
        let agent = try await sandbox.getAgentClient()
        let config = try sandbox.getConnectionConfig()

        try await agent.initDomain(config: config)
    }

    @Test func initDomainThrowsUnknownHost() async throws {
        let (agent, listener) = try Self.makeBareAgent()
        defer { listener.cancel() }

        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "unknown",
            port: 22,
            user: "user",
            path: "/home/user",
            authMethod: .none,
        )

        await #expect(throws: AgentError.unknownHost) {
            try await agent.initDomain(config: config)
        }
    }

    @Test func initDomainThrowsConnectionRefused() async throws {
        let (agent, listener) = try Self.makeBareAgent()
        defer { listener.cancel() }

        let config = ConnectionConfig(
            id: UUID(),
            name: "test",
            host: "localhost",
            port: 2223,
            user: "user",
            path: "/home/user",
            authMethod: .none,
        )

        await #expect(throws: AgentError.connectionRefused) {
            try await agent.initDomain(config: config)
        }
    }
}
