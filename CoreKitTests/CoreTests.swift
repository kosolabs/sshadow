import Common
import SwiftData
import Testing

@testable import CoreKit

struct CoreTests {
    @Test func pollSucceeds() async throws {
        let sandbox = TestSandbox()

        try await sandbox.pollAll()
    }

    @Test func currentAnchorAdvancesOnPoll() async throws {
        let sandbox = TestSandbox()

        #expect(try await sandbox.client.currentAnchor() == 0)

        try sandbox.createFolder(at: "new.txt")
        try await sandbox.pollAll()

        #expect(try await sandbox.client.currentAnchor() > 0)
    }
}
