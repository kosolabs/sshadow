import Common
import FileProvider
import SwiftLibSSH

struct Session {
    let name: String
    let config: ConnectionConfig
    let ssh: SSHClient
    let sftp: SFTPClient

    func path(for itemIdentifier: NSFileProviderItemIdentifier) -> String {
        config.path(for: itemIdentifier)
    }
}

actor SessionManager {
    let name: String
    let config: ConnectionConfig?
    private var session: Session? = nil

    init(name: String, config: ConnectionConfig?) {
        self.name = name
        self.config = config
    }

    func getSession() async throws -> Session {
        if let session = self.session {
            return session
        }

        guard let config = self.config else {
            throw NSFileProviderError(.notAuthenticated)
        }
        let ssh = try await SSHClient.connect(config: config)
        let sftp = try await ssh.sftp()
        
        let session = Session(
            name: name,
            config: config,
            ssh: ssh,
            sftp: sftp
        )
        return session
    }

    func close() async {
        guard let session = self.session else {
            return
        }
        await session.sftp.close()
        await session.ssh.close()
        self.session = nil
    }
}
