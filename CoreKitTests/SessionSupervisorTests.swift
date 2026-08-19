import Common
import FileProvider
import Foundation
import SwiftData
import Testing

@testable import CoreKit

private actor SpyXPCBroker: XPCBroker {
    enum Call: Equatable {
        case broker
        case teardown
    }

    private(set) var calls: [Call] = []

    func broker(exporting service: CoreService) async {
        calls.append(.broker)
    }

    func teardown() async {
        calls.append(.teardown)
    }
}

private actor SpyExtensionController: ExtensionController {
    enum Call: Equatable {
        case resume
        case suspend
        case remove
    }

    private(set) var calls: [Call] = []
    private(set) var suspendReason: String?
    private(set) var suspendOptions: NSFileProviderManager.DisconnectionOptions?

    func resume() async {
        calls.append(.resume)
    }

    func suspend(
        reason: String,
        options: NSFileProviderManager.DisconnectionOptions
    ) async {
        calls.append(.suspend)
        suspendReason = reason
        suspendOptions = options
    }

    func remove() async {
        calls.append(.remove)
    }
}

private actor SpySessionProvider {
    private let base: Session.Provider
    private var failuresRemaining: Int
    private var failureError: ConnectionError = .connectionRefused

    private(set) var callCount = 0
    private(set) var capturedHandler: Session.ConnectionLostHandler?
    private(set) var capturedConfig: ConnectionConfig?

    init(base: @escaping Session.Provider, failuresBeforeSuccess: Int = 0) {
        self.base = base
        self.failuresRemaining = failuresBeforeSuccess
    }

    /// Arm the provider to fail its next `count` connects with `error` before
    /// succeeding.
    func failNextConnects(
        _ count: Int,
        with error: ConnectionError = .connectionRefused
    ) {
        failuresRemaining = count
        failureError = error
    }

    nonisolated func provider() -> Session.Provider {
        { config, handler in
            try await self.connect(config, handler)
        }
    }

    private func connect(
        _ config: ConnectionConfig,
        _ handler: @escaping Session.ConnectionLostHandler
    ) async throws(ConnectionError) -> Session {
        callCount += 1
        capturedHandler = handler
        capturedConfig = config
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw failureError
        }
        return try await base(config, handler)
    }
}

private final class StatusSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var _statuses: [ConnectionStatus] = []

    var statuses: [ConnectionStatus] {
        lock.withLock { _statuses }
    }

    func handler() -> SessionSupervisor.StatusChangeHandler {
        { status in
            self.lock.withLock { self._statuses.append(status) }
        }
    }
}

extension TestSandbox {
    fileprivate func sessionProvider() async throws -> Session.Provider {
        try await Session.provider(
            domainDb: DomainDB.open(
                config: ModelConfiguration(isStoredInMemoryOnly: true)
            ),
            sharedUrl: shared,
            signalEnumerator: { _ in },
            transfers: Transfers()
        )
    }
}

private func waitUntilOnline(
    _ supervisor: SessionSupervisor,
    timeout: Duration = .seconds(5)
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if (try? await supervisor.withSession { _ in true }) == true {
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Supervisor did not come online within \(timeout)")
}

struct SessionSupervisorTests {
    @Test func withSessionThrowsWhenOffline() async throws {
        let sandbox = TestSandbox()
        let supervisor = try await SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            openSession: sandbox.sessionProvider(),
            xpc: SpyXPCBroker(),
            ext: SpyExtensionController(),
            onStatusChange: { _ in }
        )

        await #expect(throws: CoreError.serverUnreachable) {
            try await supervisor.withSession { _ in }
        }
    }

    @Test func connectResumesBrokersAndServesSession() async throws {
        let sandbox = TestSandbox()
        let xpc = SpyXPCBroker()
        let ext = SpyExtensionController()
        let provider = try await SpySessionProvider(
            base: sandbox.sessionProvider()
        )
        let supervisor = SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            openSession: provider.provider(),
            xpc: xpc,
            ext: ext,
            onStatusChange: { _ in }
        )

        try await supervisor.connect(config: try sandbox.config)

        #expect(await provider.callCount == 1)
        #expect(await ext.calls == [.resume])
        #expect(await xpc.calls == [.broker])

        let online = try await supervisor.withSession { _ in true }
        #expect(online)

        await supervisor.disable()
    }

    @Test func connectThrowsAndStaysOfflineWhenConnectFails() async throws {
        let sandbox = TestSandbox()
        let xpc = SpyXPCBroker()
        let ext = SpyExtensionController()
        let provider = try await SpySessionProvider(
            base: sandbox.sessionProvider(),
            failuresBeforeSuccess: 1
        )
        let supervisor = SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            openSession: provider.provider(),
            xpc: xpc,
            ext: ext,
            onStatusChange: { _ in }
        )

        // connect() surfaces the failure rather than retrying, and the
        // supervisor stays offline without brokering or resuming.
        await #expect(throws: ConnectionError.connectionRefused) {
            try await supervisor.connect(config: try sandbox.config)
        }
        #expect(await provider.callCount == 1)
        #expect(await ext.calls.isEmpty)
        #expect(await xpc.calls.isEmpty)

        await #expect(throws: CoreError.serverUnreachable) {
            try await supervisor.withSession { _ in }
        }
    }

    @Test func reconnectRetriesUntilConnectSucceeds() async throws {
        let sandbox = TestSandbox()
        let provider = try await SpySessionProvider(
            base: sandbox.sessionProvider()
        )
        let supervisor = SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            initialBackoff: .milliseconds(1),
            maxBackoff: .milliseconds(5),
            openSession: provider.provider(),
            xpc: SpyXPCBroker(),
            ext: SpyExtensionController(),
            onStatusChange: { _ in }
        )

        // First connect succeeds, then arm two failures for the reconnects
        // that follow a lost connection.
        try await supervisor.connect(config: try sandbox.config)
        #expect(await provider.callCount == 1)
        await provider.failNextConnects(2)

        // Losing the connection triggers a reconnect that retries through the
        // two failures before the third attempt succeeds.
        let handler = try #require(await provider.capturedHandler)
        await handler()

        try await waitUntilOnline(supervisor)
        #expect(await provider.callCount == 4)

        await supervisor.disable()
    }

    @Test func connectionLostSuspendsThenReconnects() async throws {
        let sandbox = TestSandbox()
        let xpc = SpyXPCBroker()
        let ext = SpyExtensionController()
        let provider = try await SpySessionProvider(
            base: sandbox.sessionProvider()
        )
        let supervisor = SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            initialBackoff: .milliseconds(1),
            maxBackoff: .milliseconds(5),
            openSession: provider.provider(),
            xpc: xpc,
            ext: ext,
            onStatusChange: { _ in }
        )

        try await supervisor.connect(config: try sandbox.config)
        #expect(await provider.callCount == 1)

        // Simulate the session reporting a lost connection.
        let handler = try #require(await provider.capturedHandler)
        await handler()

        // Going offline suspends the domain temporarily and tears down XPC.
        #expect(await ext.calls.contains(.suspend))
        #expect(await ext.suspendOptions?.contains(.temporary) == true)
        #expect(await xpc.calls.contains(.teardown))

        // The supervisor should automatically reconnect.
        try await waitUntilOnline(supervisor)
        #expect(await provider.callCount == 2)

        await supervisor.disable()
    }

    @Test func disableRemovesRatherThanSuspends() async throws {
        let sandbox = TestSandbox()
        let xpc = SpyXPCBroker()
        let ext = SpyExtensionController()
        let provider = try await SpySessionProvider(
            base: sandbox.sessionProvider()
        )
        let supervisor = SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            openSession: provider.provider(),
            xpc: xpc,
            ext: ext,
            onStatusChange: { _ in }
        )

        try await supervisor.connect(config: try sandbox.config)
        await supervisor.disable()

        // disable() removes the domain; it must not suspend it.
        #expect(await ext.calls == [.resume, .remove])
        #expect(await xpc.calls == [.broker, .teardown])

        await #expect(throws: CoreError.serverUnreachable) {
            try await supervisor.withSession { _ in }
        }
    }

    @Test func pauseSuspendsAndClosesRatherThanRemoves() async throws {
        let sandbox = TestSandbox()
        let xpc = SpyXPCBroker()
        let ext = SpyExtensionController()
        let provider = try await SpySessionProvider(
            base: sandbox.sessionProvider()
        )
        let supervisor = SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            openSession: provider.provider(),
            xpc: xpc,
            ext: ext,
            onStatusChange: { _ in }
        )

        try await supervisor.connect(config: try sandbox.config)
        await supervisor.pause()

        // pause() suspends the domain (preserving the cache); it must not
        // remove it the way disable() does.
        #expect(await ext.calls == [.resume, .suspend])
        #expect(await ext.suspendOptions?.contains(.temporary) == true)
        #expect(
            await ext.suspendReason
                == "The connection is paused. Reconnect it in Settings."
        )
        #expect(await xpc.calls == [.broker, .teardown])

        // The session is closed, so the supervisor is offline.
        await #expect(throws: CoreError.serverUnreachable) {
            try await supervisor.withSession { _ in }
        }
    }

    @Test func reconnectGoesOfflineOnPermanentFailure() async throws {
        let sandbox = TestSandbox()
        let spy = StatusSpy()
        let provider = try await SpySessionProvider(
            base: sandbox.sessionProvider()
        )
        let supervisor = SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            initialBackoff: .milliseconds(1),
            maxBackoff: .milliseconds(5),
            openSession: provider.provider(),
            xpc: SpyXPCBroker(),
            ext: SpyExtensionController(),
            onStatusChange: spy.handler()
        )

        try await supervisor.connect(config: try sandbox.config)
        #expect(await provider.callCount == 1)

        // Arm a permanent failure (bad credentials) for the reconnect that
        // follows a lost connection.
        await provider.failNextConnects(1, with: .authenticationFailed)
        let handler = try #require(await provider.capturedHandler)
        await handler()

        // The supervisor settles into offline(.failed) rather than retrying.
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if spy.statuses.last == .offline(.failed(.authenticationFailed)) {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(spy.statuses.last == .offline(.failed(.authenticationFailed)))

        // Only the single reconnect attempt ran; the permanent failure short
        // circuits the backoff loop instead of retrying.
        #expect(await provider.callCount == 2)

        // Give any errant retry a chance to fire, then confirm none did.
        try await Task.sleep(for: .milliseconds(20))
        #expect(await provider.callCount == 2)

        // The supervisor stays offline.
        await #expect(throws: CoreError.serverUnreachable) {
            try await supervisor.withSession { _ in }
        }

        await supervisor.disable()
    }

    @Test func reconfigureFromPausedReconnectsWithNewConfig() async throws {
        let sandbox = TestSandbox()
        let xpc = SpyXPCBroker()
        let ext = SpyExtensionController()
        let provider = try await SpySessionProvider(
            base: sandbox.sessionProvider()
        )
        let supervisor = SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            openSession: provider.provider(),
            xpc: xpc,
            ext: ext,
            onStatusChange: { _ in }
        )

        try await supervisor.connect(config: try sandbox.config)
        #expect(await provider.callCount == 1)
        #expect(await provider.capturedConfig?.name == sandbox.name)

        await supervisor.pause()

        // Edit the profile in place (a new display name) and reconnect.
        let original = try sandbox.config
        let edited = ConnectionConfig(
            id: original.id,
            name: "reconfigured",
            host: original.host,
            port: original.port,
            user: original.user,
            path: original.path,
            authMethod: original.authMethod
        )
        try await supervisor.connect(config: edited)
        try await waitUntilOnline(supervisor)

        // Reconnected with the edited config, and the domain was never
        // removed, so the cache survives.
        #expect(await provider.callCount == 2)
        #expect(await provider.capturedConfig?.name == "reconfigured")
        #expect(await ext.calls.contains(.remove) == false)

        await supervisor.disable()
    }

    @Test func connectEmitsConnectingThenOnline() async throws {
        let sandbox = TestSandbox()
        let spy = StatusSpy()
        let provider = try await SpySessionProvider(
            base: sandbox.sessionProvider()
        )
        let supervisor = SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            openSession: provider.provider(),
            xpc: SpyXPCBroker(),
            ext: SpyExtensionController(),
            onStatusChange: spy.handler()
        )

        try await supervisor.connect(config: try sandbox.config)

        #expect(spy.statuses == [.connecting, .online])

        await supervisor.disable()
    }

    @Test func connectFailureEmitsFailedOfflineWithoutReconnecting()
        async throws
    {
        let sandbox = TestSandbox()
        let spy = StatusSpy()
        let provider = try await SpySessionProvider(
            base: sandbox.sessionProvider(),
            failuresBeforeSuccess: 1
        )
        let supervisor = SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            openSession: provider.provider(),
            xpc: SpyXPCBroker(),
            ext: SpyExtensionController(),
            onStatusChange: spy.handler()
        )

        // An initial connect failure surfaces as .offline(.failed) and does
        // not enter the reconnect loop; only a lost connection retries.
        await #expect(throws: ConnectionError.connectionRefused) {
            try await supervisor.connect(config: try sandbox.config)
        }

        #expect(
            spy.statuses == [.connecting, .offline(.failed(.connectionRefused))]
        )
    }

    @Test func pauseEmitsPausedOffline() async throws {
        let sandbox = TestSandbox()
        let spy = StatusSpy()
        let provider = try await SpySessionProvider(
            base: sandbox.sessionProvider()
        )
        let supervisor = SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            openSession: provider.provider(),
            xpc: SpyXPCBroker(),
            ext: SpyExtensionController(),
            onStatusChange: spy.handler()
        )

        try await supervisor.connect(config: try sandbox.config)
        await supervisor.pause()

        #expect(spy.statuses == [.connecting, .online, .offline(.paused)])
    }

    @Test func disableEmitsDisabledOffline() async throws {
        let sandbox = TestSandbox()
        let spy = StatusSpy()
        let provider = try await SpySessionProvider(
            base: sandbox.sessionProvider()
        )
        let supervisor = SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            openSession: provider.provider(),
            xpc: SpyXPCBroker(),
            ext: SpyExtensionController(),
            onStatusChange: spy.handler()
        )

        try await supervisor.connect(config: try sandbox.config)
        await supervisor.disable()

        #expect(spy.statuses == [.connecting, .online, .offline(.disabled)])
    }

    @Test func connectionLostEmitsReconnectingWithErrorThenOnline()
        async throws
    {
        let sandbox = TestSandbox()
        let spy = StatusSpy()
        let provider = try await SpySessionProvider(
            base: sandbox.sessionProvider()
        )
        let supervisor = SessionSupervisor(
            domain: sandbox.domain,
            pollInterval: nil,
            initialBackoff: .milliseconds(1),
            maxBackoff: .milliseconds(5),
            openSession: provider.provider(),
            xpc: SpyXPCBroker(),
            ext: SpyExtensionController(),
            onStatusChange: spy.handler()
        )

        try await supervisor.connect(config: try sandbox.config)

        // Arm one failure so the first reconnect attempt fails, surfacing the
        // error and a scheduled next attempt before the retry succeeds.
        await provider.failNextConnects(1)
        let handler = try #require(await provider.capturedHandler)
        await handler()

        try await waitUntilOnline(supervisor)

        // The reconnect surfaced the underlying error and a countdown target.
        let sawReconnectingWithError = spy.statuses.contains { status in
            if case .reconnecting(.connectionRefused, let nextAttempt) = status
            {
                return nextAttempt != nil
            }
            return false
        }
        #expect(sawReconnectingWithError)

        // ...and the supervisor ends up back online.
        #expect(spy.statuses.last == .online)

        await supervisor.disable()
    }
}
