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

    @discardableResult
    func connect(id: UUID) async throws -> Session {
        try await supervisor(for: id).connect()
    }

    func disconnect(id: UUID) async {
        if let supervisor = supervisors.removeValue(forKey: id) {
            await supervisor.shutdown()
        }
    }

    func poll(id: UUID) async throws {
        let session = try await connect(id: id)
        try await session.poll()
    }

    public func register(config: ConnectionConfig) async throws {
        try await DomainDB.open(config: DomainDB.model(for: config.id))
        configs[config.id] = config
    }

    public func forget(id: UUID) async throws {
        await disconnect(id: id)
        configs[id] = nil
        try await DomainDB.delete(id: id)
    }

    public func broker(id: UUID) async throws {
        try await supervisor(for: id).broker()
    }

    public func teardown(id: UUID) async {
        await supervisors[id]?.teardown()
    }
}
