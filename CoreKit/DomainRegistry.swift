import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "DomainRegistry")

public actor DomainRegistry {
    typealias DomainSignal = @Sendable (ConnectionConfig) async -> Void
    typealias MaterializedEnumerator =
        @Sendable (ConnectionConfig) throws -> any NSFileProviderEnumerator
    typealias DomainLister = @Sendable () async -> [NSFileProviderDomain]
    typealias DomainRemover = @Sendable (NSFileProviderDomain) async -> Void
    typealias DomainDeleter = @Sendable (UUID) -> Void

    public static let shared: DomainRegistry = DomainRegistry(
        signalChanges: { config in
            await config.domain.signalChanges()
        },
        retryExcluded: { config in
            await config.domain.retryIgnored()
        },
        materializedItems: { config in
            try config.domain.manager.enumeratorForMaterializedItems()
        },
        pollInterval: .seconds(300),
        connections: Connections.shared,
        transfers: Transfers.shared,
        events: Events.shared
    )

    private let groupUrl: URL
    private let signalChanges: DomainSignal
    private let retryExcluded: DomainSignal
    private let materializedItems: MaterializedEnumerator
    private let pollInterval: Duration?
    private let connections: Connections
    private let transfers: Transfers<ContinuousClock>
    private let events: Events<ContinuousClock>
    private let listDomains: DomainLister
    private let removeDomain: DomainRemover
    private let deleteDomain: DomainDeleter

    private var supervisors: [UUID: SessionSupervisor] = [:]
    private var pending: [UUID: Task<SessionSupervisor, Error>] = [:]

    init(
        groupUrl: URL = SSHadow.groupUrl,
        signalChanges: @escaping DomainSignal,
        retryExcluded: @escaping DomainSignal,
        materializedItems: @escaping MaterializedEnumerator,
        pollInterval: Duration? = nil,
        connections: Connections,
        transfers: Transfers<ContinuousClock>,
        events: Events<ContinuousClock>,
        listDomains: @escaping DomainLister = {
            await NSFileProviderDomain.all()
        },
        removeDomain: @escaping DomainRemover = {
            await $0.remove()
        },
        deleteDomainDB: @escaping DomainDeleter = {
            DomainDB.delete(id: $0)
        }
    ) {
        self.groupUrl = groupUrl
        self.signalChanges = signalChanges
        self.retryExcluded = retryExcluded
        self.materializedItems = materializedItems
        self.pollInterval = pollInterval
        self.connections = connections
        self.transfers = transfers
        self.events = events
        self.listDomains = listDomains
        self.removeDomain = removeDomain
        self.deleteDomain = deleteDomainDB
    }

    private func supervisor(
        for domain: NSFileProviderDomain
    ) async throws -> SessionSupervisor {
        if let supervisor = supervisors[domain.id] { return supervisor }
        if let task = pending[domain.id] { return try await task.value }

        let task = Task {
            let domainDb = try await DomainDB.open(domainId: domain.id)

            let supervisor = SessionSupervisor(
                domain: domain,
                pollInterval: pollInterval,
                openSession: Session.provider(
                    domainDb: domainDb,
                    groupUrl: groupUrl,
                    signalChanges: signalChanges,
                    retryIgnored: retryExcluded,
                    materializedItems: materializedItems,
                    transfers: transfers,
                    events: events
                ),
                events: events,
                onStatusChange: { status in
                    self.connections.update(status, for: domain.id)
                }
            )
            supervisors[domain.id] = supervisor
            return supervisor
        }

        pending[domain.id] = task
        defer { pending[domain.id] = nil }
        return try await task.value
    }

    public func connect(config: ConnectionConfig) async throws {
        try await supervisor(for: config.domain).connect(config: config)
    }

    public func reconnect(config: ConnectionConfig) async throws {
        try await supervisor(for: config.domain).reconnect(config: config)
    }

    public func poll(domain: NSFileProviderDomain) async throws {
        if let supervisor = supervisors[domain.id] {
            try await supervisor.withSession { try await $0.pollAll() }
        } else {
            logger.error("Failed to poll missing supervisor: \(domain)")
        }
    }

    public func pause(domain: NSFileProviderDomain) async {
        if let supervisor = supervisors[domain.id] {
            await supervisor.pause()
        }
    }

    public func disable(domain: NSFileProviderDomain) async {
        if let task = pending[domain.id] {
            _ = try? await task.value
        }
        if let supervisor = supervisors.removeValue(forKey: domain.id) {
            await supervisor.disable()
            DomainDB.delete(id: domain.id)
        }
    }

    public func removeOrphanedDomains(enabledIds: Set<UUID>) async {
        for domain in await listDomains() {
            guard supervisors[domain.id] == nil, pending[domain.id] == nil,
                !enabledIds.contains(domain.id)
            else { continue }
            await removeDomain(domain)
            guard supervisors[domain.id] == nil, pending[domain.id] == nil
            else { continue }
            deleteDomain(domain.id)
            logger.notice("Removed orphaned domain: \(domain)")
        }
    }
}
