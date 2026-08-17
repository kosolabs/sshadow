import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "DomainRegistry")

typealias EnumeratorSignal =
    @Sendable (ConnectionConfig) async throws -> Void

public actor DomainRegistry {
    public static let shared: DomainRegistry = DomainRegistry(
        signalEnumerator: { config in
            try await config.domain.manager.signalEnumerator(
                for: .workingSet
            )
        },
        connections: Connections.shared,
        transfers: Transfers.shared,
        pollInterval: .seconds(30),
    )

    private let sharedUrl: URL
    private let signalEnumerator: EnumeratorSignal
    private let connections: Connections
    private let transfers: Transfers
    private let pollInterval: Duration?

    private var supervisors: [UUID: SessionSupervisor] = [:]

    init(
        sharedUrl: URL = SSHadow.groupUrl,
        signalEnumerator: @escaping EnumeratorSignal,
        connections: Connections,
        transfers: Transfers,
        pollInterval: Duration? = nil
    ) {
        self.sharedUrl = sharedUrl
        self.signalEnumerator = signalEnumerator
        self.connections = connections
        self.transfers = transfers
        self.pollInterval = pollInterval
    }

    private func supervisor(for id: UUID) throws -> SessionSupervisor {
        guard let supervisor = supervisors[id] else {
            throw CoreError.profileNotFound
        }
        return supervisor
    }

    public func enable(config: ConnectionConfig) async throws {
        let domainDb = try await DomainDB.open(config: DomainDB.model(for: config.id))

        let supervisor = SessionSupervisor(
            config: config,
            pollInterval: pollInterval,
            openSession: Session.provider(
                domainDb: domainDb,
                sharedUrl: sharedUrl,
                signalEnumerator: signalEnumerator,
                transfers: transfers
            ),
            onStatusChange: { status in
                self.connections.update(status, for: config.id)
            }
        )
        supervisors[config.id] = supervisor

        try await supervisor.connect()
    }

    public func poll(id: UUID) async throws {
        try await supervisor(for: id).withSession { try await $0.poll() }
    }

    public func pause(id: UUID) async throws {
        try await supervisor(for: id).pause()
    }

    public func reconfigure(config: ConnectionConfig) async throws {
        try await supervisor(for: config.id).reconfigure(config: config)
    }

    public func disable(id: UUID) async throws {
        if let supervisor = supervisors.removeValue(forKey: id) {
            await supervisor.disable()
        }
    }
}
