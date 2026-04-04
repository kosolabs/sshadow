import Common
import FileProvider
import SwiftLibSSH

private let logger = Logger(category: "SessionManager")

actor SessionManager {
    nonisolated let domain: NSFileProviderDomain
    nonisolated let config: ConnectionConfig?
    private var session: Session? = nil
    
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

        guard let config = self.config else {
            throw NSFileProviderError(.notAuthenticated)
        }
        
        let ssh: SSHClient, sftp: SFTPClient, db: SSHadowDB
        do {
            ssh = try await SSHClient.connect(config: config)
            sftp = try await ssh.sftp()
            db = try SSHadowDB(domain: domain)
        } catch SSHError.authenticationFailed(_) {
            throw NSFileProviderError(.notAuthenticated)
        } catch SSHError.connectionFailed(_) {
            throw NSFileProviderError(.serverUnreachable)
        }

        let session = Session(
            domain: domain,
            config: config,
            ssh: ssh,
            sftp: sftp,
            db: db
        )

        self.session = session
        logger.info("Connected: \(session.config.url)")
        return session
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
