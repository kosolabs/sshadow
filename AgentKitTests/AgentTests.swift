import Common
import SwiftData
import Testing

@testable import AgentKit

struct AgentTests {
    @Test func pollSucceeds() async throws {
        let sandbox = TestSandbox()

        try await sandbox.agent.poll(domainId: sandbox.id)
    }

    @Test func currentAnchorAdvancesOnPoll() async throws {
        let sandbox = TestSandbox()

        #expect(try await sandbox.client.currentAnchor() == 0)

        try sandbox.createFolder(at: "new.txt")
        try await sandbox.agent.poll(domainId: sandbox.id)

        #expect(try await sandbox.client.currentAnchor() == 1)
    }
}
