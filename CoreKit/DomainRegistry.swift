import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "DomainRegistry")

public actor DomainRegistry {
    typealias EnumeratorSignal =
        @Sendable (ConnectionConfig) async throws -> Void

    public static let shared: DomainRegistry = DomainRegistry(
        signalEnumerator: { config in
            try await config.domain.manager.signalEnumerator(
                for: .workingSet
            )
        },
        connections: Connections.shared,
        transfers: Transfers.shared,
        pollInterval: .seconds(300),
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

    private func supervisor(
        for domain: NSFileProviderDomain
    ) async throws -> SessionSupervisor {
        if let supervisor = supervisors[domain.id] {
            return supervisor
        }

        let domainDb = try await DomainDB.open(domainId: domain.id)

        let supervisor = SessionSupervisor(
            domain: domain,
            pollInterval: pollInterval,
            openSession: Session.provider(
                domainDb: domainDb,
                sharedUrl: sharedUrl,
                signalEnumerator: signalEnumerator,
                transfers: transfers
            ),
            onStatusChange: { status in
                self.connections.update(status, for: domain.id)
            }
        )
        supervisors[domain.id] = supervisor
        return supervisor
    }

    public func connect(config: ConnectionConfig) async throws {
        try await supervisor(for: config.domain).connect(config: config)
    }

    public func poll(domain: NSFileProviderDomain) async throws {
        try await supervisor(for: domain).withSession { try await $0.pollAll() }
    }

    public func pause(domain: NSFileProviderDomain) async throws {
        try await supervisor(for: domain).pause()
    }

    public func disable(domain: NSFileProviderDomain) async throws {
        if let supervisor = supervisors.removeValue(forKey: domain.id) {
            await supervisor.disable()
        }
    }
}
