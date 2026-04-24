import FileProvider
import Foundation
import Testing

@testable import Common

struct AgentClientTests {
    @Test func agentSayHelloSucceeds() async throws {
        let agent = TestData.getAgentClient()
        let result = try await agent.sayHello(to: "Unit Tests")
        #expect(result == "Hello, Unit Tests!")
    }
}
