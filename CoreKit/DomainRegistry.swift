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

    private let domainDbConfig: ModelConfiguration?
    private let sharedUrl: URL
    private let signal: SignalEnumerator
    private let transfers: Transfers
    private let pollInterval: Duration?

    private var configs: [UUID: ConnectionConfig] = [:]
    private var supervisors: [UUID: Task<SessionSupervisor, Never>] = [:]

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

    private func supervisor(for id: UUID) async throws -> SessionSupervisor {
        if let task = supervisors[id] {
            return await task.value
        }

        guard let config = configs[id] else {
            throw CoreError.profileNotFound
        }

        let task = Task {
            await SessionSupervisor(
                config: config,
                domainDbConfig: domainDbConfig ?? DomainDB.model(for: id),
                sharedUrl: sharedUrl,
                signal: signal,
                transfers: transfers,
                pollInterval: pollInterval
            )
        }
        supervisors[id] = task
        return await task.value
    }

    @discardableResult
    func withSession<T: Sendable>(
        id: UUID,
        _ operation: @Sendable (Session) async throws -> T
    ) async throws -> T {
        try await supervisor(for: id).withSession(operation)
    }

    func poll(id: UUID) async throws {
        try await withSession(id: id) { session in
            try await session.poll()
        }
    }

    @discardableResult
    func connect(id: UUID) async throws -> Session {
        try await supervisor(for: id).connect()
    }

    func disconnect(id: UUID) async {
        if let task = supervisors.removeValue(forKey: id) {
            await task.value.disconnect()
        }
    }

    public func register(config: ConnectionConfig) async throws {
        try await DomainDB.open(
            config: domainDbConfig ?? DomainDB.model(for: config.id)
        )
        configs[config.id] = config
        try await connect(id: config.id)
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
        await supervisors[id]?.value.teardown()
    }
}
