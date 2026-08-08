import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "DomainRegistry")

public actor DomainRegistry {
    public static let shared: DomainRegistry = DomainRegistry(
        signal: { config in
            try await config.domain.manager.signalEnumerator(
                for: .workingSet
            )
        },
        transfers: Transfers.shared,
        pollInterval: .seconds(30),
    )

    private let sharedUrl: URL
    private let signal: SignalEnumerator
    private let transfers: Transfers
    private let pollInterval: Duration?

    private var configs: [UUID: ConnectionConfig] = [:]
    private var supervisors: [UUID: SessionSupervisor] = [:]

    init(
        sharedUrl: URL = SSHadow.groupUrl,
        signal: @escaping SignalEnumerator,
        transfers: Transfers,
        pollInterval: Duration? = nil
    ) {
        self.sharedUrl = sharedUrl
        self.signal = signal
        self.transfers = transfers
        self.pollInterval = pollInterval
    }

    func supervisor(for id: UUID) throws -> SessionSupervisor {
        if let supervisor = supervisors[id] {
            return supervisor
        }

        guard let config = configs[id] else {
            throw CoreError.profileNotFound
        }

        let supervisor = SessionSupervisor(
            config: config,
            domainDbConfig: DomainDB.model(for: id),
            sharedUrl: sharedUrl,
            signal: signal,
            transfers: transfers,
            pollInterval: pollInterval
        )
        supervisors[id] = supervisor
        return supervisor
    }

    func poll(id: UUID) async throws {
        try await supervisor(for: id).withSession { try await $0.poll() }
    }

    public func enable(config: ConnectionConfig) async throws {
        try await DomainDB.open(config: DomainDB.model(for: config.id))
        configs[config.id] = config
        try await supervisor(for: config.id).enable()
    }
    
    public func disable(id: UUID) async throws {
        if let supervisor = supervisors.removeValue(forKey: id) {
            await supervisor.disable()
        }
        configs[id] = nil
    }
}
