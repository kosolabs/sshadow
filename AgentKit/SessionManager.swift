import Common
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "SessionManager")

actor SessionManager {
    private let db: AppDB
    private var sessions: [UUID: Session] = [:]
    private var connectTasks: [UUID: Task<Session, any Error>] = [:]

    init(appDbStorePath: URL? = nil) {
        if let appDbStorePath = appDbStorePath {
            logger.info("Using: \(appDbStorePath)")
            self.db = try! AppDB.open(
                config: ModelConfiguration(url: appDbStorePath)
            )
        } else {
            self.db = try! AppDB.open()
        }
    }

    func connect(id: UUID) async throws -> Session {
        guard let profile = await db.fetch(id: id) else {
            throw AgentError.profileNotFound(id)
        }

        let config = try ConnectionConfig(from: profile)

        if let session = sessions[config.id] {
            return session
        }

        if let task = connectTasks[config.id] {
            return try await task.value
        }

        let task = Task {
            let ssh = try await SSHClient.connect(config: config)
            let sftp = try await ssh.sftp()
            let userInfo = try UserInfo(from: profile)
            let domain = try profile.getDomain(with: userInfo)
            let db = try await SSHadowDB.open(domain: domain)
            return Session(config: config, ssh: ssh, sftp: sftp, db: db)
        }
        connectTasks[config.id] = task

        do {
            let session = try await task.value
            sessions[config.id] = session
            connectTasks[config.id] = nil
            logger.info("Connected: \(config.url)")
            return session
        } catch {
            connectTasks[config.id] = nil
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
