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
        guard let profile = await db.fetch(id: id) else {
            throw AgentError.profileNotFound(id)
        }

        if let session = sessions[id] {
            return session
        }

        if let task = connectTasks[id] {
            return try await task.value
        }

        let domainDbConfig = self.domainDbConfig ?? DomainDB.model(for: id)
        let task = Task {
            let config = try ConnectionConfig(from: profile)
            let ssh = try await SSHClient.connect(profile: profile)
            let sftp = try await ssh.sftp()
            let db = try await DomainDB.open(config: domainDbConfig)
            return Session(config: config, ssh: ssh, sftp: sftp, db: db)
        }
        connectTasks[id] = task

        do {
            let session = try await task.value
            sessions[id] = session
            connectTasks[id] = nil
            logger.info("Connected: \(profile.url)")
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
        }
    }

    func disconnectAll() async {
        for id in sessions.keys {
            await disconnect(id: id)
        }
    }
}
