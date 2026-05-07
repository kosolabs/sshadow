import Common
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "SessionManager")

actor SessionManager {
    private let db: AppDB
    private let domainDbConfig: ModelConfiguration?
    private var sessions: [UUID: Session] = [:]
    private var connectTasks: [UUID: Task<Session, any Error>] = [:]

    init(appDb: AppDB, domainDbConfig: ModelConfiguration? = nil) {
        self.db = appDb
        self.domainDbConfig = domainDbConfig
    }

    func connect(id: UUID) async throws -> Session {
        if let session = sessions[id] {
            return session
        }

        if let task = connectTasks[id] {
            return try await task.value
        }

        guard let profile = await db.fetch(id: id) else {
            throw AgentError.notAuthenticated
        }
        let config = try ConnectionConfig(from: profile)

        logger.info("Connecting: \(config.url)")
        let domainDbConfig = self.domainDbConfig ?? DomainDB.model(for: id)
        let task = Task {
            let ssh = try await SSHClient.connect(config: config)
            let sftp = try await ssh.sftp()
            let db = try await DomainDB.open(config: domainDbConfig)
            return Session(config: config, ssh: ssh, sftp: sftp, db: db)
        }
        connectTasks[id] = task

        do {
            let session = try await task.value
            sessions[id] = session
            connectTasks[id] = nil
            logger.info("Connected: \(config.url)")
            return session
        } catch {
            connectTasks[id] = nil
            throw error
        }
    }

    func disconnect(id: UUID) async {
        connectTasks[id]?.cancel()
        connectTasks[id] = nil
        if let session = sessions.removeValue(forKey: id) {
            await session.close()
            logger.info("Disconnected: \(session.url)")
        }
    }

    func disconnectAll() async {
        for id in sessions.keys {
            await disconnect(id: id)
        }
    }
}
