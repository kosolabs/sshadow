import Common
import FileProvider
import Foundation
import Testing

@testable import CoreKit

/// Thread-safe tally of `attach`/`detach` calls the spy receives over XPC.
private actor Tally {
    private(set) var attaches = 0
    private(set) var detaches = 0
    func bumpAttach() { attaches += 1 }
    func bumpDetach() { detaches += 1 }
}

/// Stands in for the extension: vends an `ExtXPC` over an anonymous listener and
/// records `attach`/`detach`, so `DomainLink` can be brokered without a live
/// File Provider domain.
private final class ExtSpy: NSObject, NSXPCListenerDelegate, ExtXPC,
    @unchecked Sendable
{
    let listener = NSXPCListener.anonymous()
    let tally = Tally()

    private let lock = NSLock()
    private var accepted: [NSXPCConnection] = []

    override init() {
        super.init()
        listener.delegate = self
        listener.resume()
    }

    var endpoint: NSXPCListenerEndpoint { listener.endpoint }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ExtXPC.self)
        connection.exportedObject = self
        connection.remoteObjectInterface = NSXPCInterface(with: CoreXPC.self)
        connection.resume()

        lock.lock()
        accepted.append(connection)
        lock.unlock()
        return true
    }

    func attach() async { await tally.bumpAttach() }
    func detach() async { await tally.bumpDetach() }

    /// Drops the most recently accepted connection to simulate the link
    /// breaking, which fires the peer's invalidation handler.
    func invalidateLatest() {
        lock.lock()
        let connection = accepted.last
        lock.unlock()
        connection?.invalidate()
    }
}

/// Minimal `CoreXPC` to serve as the exported object; never invoked by the spy.
private final class CoreStub: NSObject, CoreXPC {
    func handle(_ data: Data) async throws -> Data { Data() }
    func handle(
        _ data: Data,
        progressEndpoint: NSXPCListenerEndpoint
    ) async throws -> Data { Data() }
}

private func eventually(
    timeout: Duration = .seconds(10),
    _ condition: @Sendable () async throws -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if try await condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Condition not met within \(timeout)")
}

private func makeLink(spy: ExtSpy) -> DomainLink {
    DomainLink(
        domain: NSFileProviderDomain(id: UUID(), displayName: "Test"),
        exportedObject: CoreStub(),
        resume: {},
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
