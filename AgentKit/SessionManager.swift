import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "SessionManager")

actor SessionManager {
    private let domainDbConfig: ModelConfiguration?
    private let sharedUrl: URL
    private let signal: SignalEnumerator
    private let transfers: Transfers
    private let pollInterval: Duration?

    private var configs: [UUID: ConnectionConfig] = [:]
    private var sessions: [UUID: Session] = [:]
    private var connectTasks: [UUID: Task<Session, any Error>] = [:]

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
        if let session = sessions[id] {
            return session
        }

        guard let config = configs[id] else {
            throw AgentError.profileNotFound
        }

        if let task = connectTasks[id] {
            return try await task.value
        }

        let domainDbConfig = domainDbConfig ?? DomainDB.model(for: id)

        let task = Task {
            let ssh = try await SSHClient.connect(config: config)
            let sftp = try await ssh.sftp()
            let db = try await DomainDB.open(config: domainDbConfig)
            return Session(
                config: config,
                ssh: ssh,
                sftp: sftp,
                db: db,
                sharedUrl: sharedUrl,
                signal: signal,
                transfers: transfers,
                pollInterval: pollInterval
            )
        }
        connectTasks[id] = task

        do {
            let session = try await task.value
            sessions[id] = session
            connectTasks[id] = nil
            await session.start()
            return session
        } catch {
            connectTasks[id] = nil
            throw error
        }
    }

    func forget(id: UUID) async {
        await disconnect(id: id)
        configs[id] = nil
    }

    func disconnect(id: UUID) async {
        connectTasks[id]?.cancel()
        connectTasks[id] = nil
        if let session = sessions.removeValue(forKey: id) {
            await session.close()
        }
    }
}
