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

        if let session = sessions[id] {
            return session
        }

        if let task = connectTasks[id] {
            return try await task.value
        }

        let task = Task {
            let ssh = try await SSHClient.connect(profile: profile)
            let sftp = try await ssh.sftp()
            let db = try await DomainDB.open(id: id)
            return Session(profile: profile, ssh: ssh, sftp: sftp, db: db)
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
