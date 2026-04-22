import Common
import FileProvider
import SwiftLibSSH

private let logger = Logger(category: "SessionManager")

private func connect(
    domain: NSFileProviderDomain,
    config: ConnectionConfig
) async throws -> Session {
    do {
        let ssh = try await SSHClient.connect(config: config)
        let sftp = try await ssh.sftp()
        let db = try await SSHadowDB.open(domain: domain)
        return Session(
            domain: domain,
            config: config,
            ssh: ssh,
            sftp: sftp,
            db: db,
            agent: AgentClient()
        )
    } catch SSHError.authenticationFailed(_) {
        throw NSFileProviderError(.notAuthenticated)
    } catch SSHError.connectionFailed(_) {
        throw NSFileProviderError(.serverUnreachable)
    }
}

actor SessionManager {
    nonisolated let domain: NSFileProviderDomain
    nonisolated let config: ConnectionConfig?
    private var session: Session? = nil
    private var connectTask: Task<Session, any Error>? = nil

    nonisolated var name: String {
        domain.displayName
    }

    init(domain: NSFileProviderDomain, config: ConnectionConfig?) {
        self.domain = domain
        self.config = config
    }

    func getSession() async throws -> Session {
        if let session = self.session {
            return session
        }
        
        if let task = connectTask {
            return try await task.value
        }

        guard let config = self.config else {
            throw NSFileProviderError(.notAuthenticated)
        }
        
        let task = Task {
            try await connect(domain: domain, config: config)
        }
        connectTask = task
        
        do {
            let session = try await task.value
            self.session = session
            logger.info("Connected: \(session.config.url)")
            connectTask = nil
            return session
        } catch {
            connectTask = nil
            throw error
        }
    }

    func close() async {
        guard let session = self.session else {
            return
        }

        await session.sftp.close()
        await session.ssh.close()

        self.session = nil
        logger.info("Disconnected: \(session.config.url)")
    }

    nonisolated func withSession<T>(
        progress: Progress = Progress(),
        _ perform: @escaping (Session, Progress) async throws -> T,
        onSuccess: @escaping (T) -> Void,
        onError: @escaping (Error) -> Void,
        file: String = #fileID,
        line: Int = #line,
    ) -> Progress {
        let trace = StackTrace.capture(file: file, line: line)

        Task {
            do {
                let session = try await self.getSession()
                let result = try await perform(session, progress)
                onSuccess(result)
            } catch {
                trace.log(logger, error: error)
                onError(error)
            }
        }
        return progress
    }
}
