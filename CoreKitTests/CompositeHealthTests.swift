import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH
import Testing

@testable import CoreKit

@Suite struct CompositeHealthTests {
    /// Builds a supervisor whose domain link records suspend/resume and brokers
    /// XPC against `spy`, so composite-health gating can be observed without a
    /// live File Provider domain. SSH still dials the real test server.
    private func makeSupervisor(
        sandbox: TestSandbox,
        recorder: DomainStateRecorder,
        spy: ExtSpy
    ) throws -> SessionSupervisor {
        let link = DomainLink(
            domain: NSFileProviderDomain(id: sandbox.id, displayName: "Test"),
            exportedObject: CoreStub(),
            connect: { NSXPCConnection(listenerEndpoint: spy.endpoint) },
            suspend: { reason in await recorder.recordSuspend(reason) },
            resume: { await recorder.recordResume() }
        )
        return SessionSupervisor(
            config: try sandbox.config,
            domainDbConfig: ModelConfiguration(isStoredInMemoryOnly: true),
            sharedUrl: sandbox.shared,
            signal: { _ in },
            transfers: Transfers(),
            pollInterval: nil,
            link: link
        )
    }

    @Test func resumesOnlyWhenSshAndXpcBothUp() async throws {
        let sandbox = TestSandbox()
        let recorder = DomainStateRecorder()
        let spy = ExtSpy()
        let supervisor = try makeSupervisor(
            sandbox: sandbox,
            recorder: recorder,
            spy: spy
        )

        // SSH connected but the XPC link is not up yet: do not resume.
        _ = try await supervisor.connect()
        #expect(await recorder.resumes == 0)

        // Both halves of composite health are now good: resume exactly once.
        try await supervisor.broker()
        #expect(await recorder.resumes == 1)
        #expect(await recorder.suspends == 0)

        // The server drops: suspend with the user-facing reason.
        await #expect(throws: SSHError.self) {
            try await supervisor.withSession { _ in
                throw SSHError.connectionFailed(message: "boom")
            }
        }
        #expect(await recorder.suspends == 1)
        #expect(await recorder.lastReason == SessionSupervisor.unreachableReason)

        // The server returns: SSH reconnects and, with XPC still up, resumes.
        _ = try await supervisor.connect()
        #expect(await recorder.resumes == 2)

        await supervisor.disconnect()
    }

    @Test func reBrokerWhileServerDownDoesNotResume() async throws {
        let sandbox = TestSandbox()
        let recorder = DomainStateRecorder()
        let spy = ExtSpy()
        let supervisor = try makeSupervisor(
            sandbox: sandbox,
            recorder: recorder,
            spy: spy
        )

        _ = try await supervisor.connect()
        try await supervisor.broker()
        #expect(await recorder.resumes == 1)

        // The server drops: domain is suspended, SSH stays down (no poll loop).
        await #expect(throws: SSHError.self) {
            try await supervisor.withSession { _ in
                throw SSHError.connectionFailed(message: "down")
            }
        }
        #expect(await recorder.suspends == 1)

        // The XPC link breaks and re-brokers while the server is still down.
        spy.invalidateLatest()
        try await eventually {
            await spy.tally.attaches == 2
        }

        // The re-broker must not resume a domain whose server is still down.
        #expect(await recorder.resumes == 1)

        await supervisor.disconnect()
    }
}
