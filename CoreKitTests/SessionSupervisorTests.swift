import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH
import Testing

@testable import CoreKit

/// Hands out real `Session`s against the test server, but can be told to fail a
/// number of the next connects with `connectionFailed` to simulate a transient
/// SSH disconnect. Holds only `Sendable` state so it can back an injected
/// `SessionFactory`.
private actor FlakyConnector {
    private let config: ConnectionConfig
    private let sharedUrl: URL
    private var failuresRemaining = 0
    private(set) var attempts = 0

    init(config: ConnectionConfig, sharedUrl: URL) {
        self.config = config
        self.sharedUrl = sharedUrl
    }

    func failNext(_ count: Int) {
        failuresRemaining += count
    }

    func connect() async throws -> Session {
        attempts += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw SSHError.connectionFailed(message: "transient")
        }
        let ssh = try await SSHClient.connect(config: config)
        let sftp = try await ssh.sftp()
        let db = try await DomainDB.open(
            config: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return Session(
            config: config,
            ssh: ssh,
            sftp: sftp,
            db: db,
            sharedUrl: sharedUrl,
            signal: { _ in },
            transfers: Transfers()
        )
    }
}

private struct NonConnectionError: Error {}

/// Polls `condition` until it holds or the timeout elapses.
extension TestSandbox {
    fileprivate func makeSupervisor(
        pollInterval: Duration? = nil,
        initialBackoff: Duration = .milliseconds(10),
        maxBackoff: Duration = .milliseconds(50),
        makeSession: SessionFactory? = nil
    ) throws -> SessionSupervisor {
        SessionSupervisor(
            config: try config,
            domainDbConfig: ModelConfiguration(isStoredInMemoryOnly: true),
            sharedUrl: shared,
            signal: { _ in },
            transfers: Transfers(),
            pollInterval: pollInterval,
            initialBackoff: initialBackoff,
            maxBackoff: maxBackoff,
            makeSession: makeSession
        )
    }
}

@Suite struct SessionSupervisorTests {
    @Test func connectReportsConnectedHealth() async throws {
        let sandbox = TestSandbox()
        let supervisor = try sandbox.makeSupervisor()

        _ = try await supervisor.connect()

        #expect(await supervisor.health == .connected)
        await supervisor.disconnect()
    }

    @Test func connectCoalescesConcurrentCallers() async throws {
        let sandbox = TestSandbox()
        let supervisor = try sandbox.makeSupervisor()

        async let first = supervisor.connect()
        async let second = supervisor.connect()
        let (s1, s2) = try await (first, second)

        #expect(s1 === s2)
        await supervisor.disconnect()
    }

    @Test func connectionFailedFromRequestDropsAndReconnects() async throws {
        let sandbox = TestSandbox()
        let supervisor = try sandbox.makeSupervisor()

        let s1 = try await supervisor.connect()
        #expect(await supervisor.health == .connected)

        // A request that fails with a connection error must drop the session.
        await #expect(throws: SSHError.self) {
            try await supervisor.withSession { _ in
                throw SSHError.connectionFailed(message: "boom")
            }
        }
        #expect(await supervisor.health == .disconnected)

        // The next connect rebuilds a fresh, working session.
        let s2 = try await supervisor.connect()
        #expect(s2 !== s1)
        #expect(await supervisor.health == .connected)
        _ = try await s2.list(for: .rootContainer)

        await supervisor.disconnect()
    }

    @Test func nonConnectionErrorKeepsSession() async throws {
        let sandbox = TestSandbox()
        let supervisor = try sandbox.makeSupervisor()

        let s1 = try await supervisor.connect()

        await #expect(throws: NonConnectionError.self) {
            try await supervisor.withSession { _ in
                throw NonConnectionError()
            }
        }

        // A non-connection failure must not drop the live session.
        #expect(await supervisor.health == .connected)
        let s2 = try await supervisor.connect()
        #expect(s2 === s1)

        await supervisor.disconnect()
    }

    @Test func pollLoopRecoversAfterTransientDisconnect() async throws {
        let sandbox = TestSandbox()
        let connector = FlakyConnector(
            config: try sandbox.config,
            sharedUrl: sandbox.shared
        )
        let supervisor = try sandbox.makeSupervisor(
            pollInterval: .milliseconds(20)
        ) {
            try await connector.connect()
        }

        // First connect succeeds and starts the poll loop.
        let s1 = try await supervisor.connect()
        #expect(await connector.attempts == 1)

        // Arrange a single transient failure on the next reconnect, then drop
        // the live session to force the poll loop to reconnect.
        await connector.failNext(1)
        await #expect(throws: SSHError.self) {
            try await supervisor.withSession { _ in
                throw SSHError.connectionFailed(message: "drop")
            }
        }

        // The loop backs off past the transient failure and reconnects: the
        // first reconnect attempt fails, the next succeeds.
        try await eventually {
            let attempts = await connector.attempts
            let health = await supervisor.health
            return attempts >= 3 && health == .connected
        }

        let s2 = try await supervisor.connect()
        #expect(s2 !== s1)

        await supervisor.disconnect()
    }
}
