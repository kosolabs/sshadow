import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "DomainRegistry")

actor DomainRegistry {
    private let domainDbConfig: ModelConfiguration?
    private let sharedUrl: URL
    private let signal: SignalEnumerator
    private let transfers: Transfers
    private let pollInterval: Duration?

    private var configs: [UUID: ConnectionConfig] = [:]
    private var supervisors: [UUID: SessionSupervisor] = [:]

    init(
        domainDbConfig: ModelConfiguration? = nil,
        sharedUrl: URL = SSHadow.groupUrl,
        signal: @escaping SignalEnumerator,
        transfers: Transfers,
        pollInterval: Duration? = nil
    ) {
        self.domainDbConfig = domainDbConfig
        self.sharedUrl = sharedUrl
        self.signal = signal
        self.transfers = transfers
        self.pollInterval = pollInterval
    }

    @discardableResult
    func register(config: ConnectionConfig) async throws -> Session {
        configs[config.id] = config
        return try await connect(id: config.id)
    }

    @discardableResult
    func connect(id: UUID) async throws -> Session {
        try await supervisor(for: id).connect()
    }

    private func supervisor(for id: UUID) throws -> SessionSupervisor {
        if let supervisor = supervisors[id] {
            return supervisor
        }

        guard let config = configs[id] else {
            throw CoreError.profileNotFound
        }

        let supervisor = SessionSupervisor(
            config: config,
            domainDbConfig: domainDbConfig ?? DomainDB.model(for: id),
            sharedUrl: sharedUrl,
            signal: signal,
            transfers: transfers,
            pollInterval: pollInterval
        )
        supervisors[id] = supervisor
        return supervisor
    }

    func forget(id: UUID) async {
        await disconnect(id: id)
        configs[id] = nil
    }

    func disconnect(id: UUID) async {
        if let supervisor = supervisors.removeValue(forKey: id) {
            await supervisor.disconnect()
        }
    }
}
