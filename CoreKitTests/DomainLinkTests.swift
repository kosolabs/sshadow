import Common
import FileProvider
import Foundation
import Testing

@testable import CoreKit

private func makeLink(spy: ExtSpy) -> DomainLink {
    DomainLink(
        domain: NSFileProviderDomain(id: UUID(), displayName: "Test"),
        exportedObject: CoreStub(),
        connect: { NSXPCConnection(listenerEndpoint: spy.endpoint) }
    )
}

@Suite struct DomainLinkTests {
    @Test func brokerAttachesExtension() async throws {
        let spy = ExtSpy()
        let link = makeLink(spy: spy)

        try await link.broker()

        // broker awaits the round-trip, so attach has completed on return.
        #expect(await spy.tally.attaches == 1)

        await link.teardown()
    }

    @Test func teardownDetachesExtension() async throws {
        let spy = ExtSpy()
        let link = makeLink(spy: spy)

        try await link.broker()
        await link.teardown()

        #expect(await spy.tally.detaches == 1)
    }

    @Test func teardownWithoutBrokerIsNoOp() async throws {
        let spy = ExtSpy()
        let link = makeLink(spy: spy)

        await link.teardown()

        #expect(await spy.tally.detaches == 0)
    }

    @Test func invalidationReBrokers() async throws {
        let spy = ExtSpy()
        let link = makeLink(spy: spy)

        try await link.broker()
        #expect(await spy.tally.attaches == 1)

        // Breaking the connection must drive a re-broker (a second attach).
        spy.invalidateLatest()
        try await eventually {
            await spy.tally.attaches == 2
        }

        await link.teardown()
    }
}
