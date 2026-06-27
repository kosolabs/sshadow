import Common
import SwiftLibSSH

private let logger = Logger(category: "SSHClient")

extension SSHClient {
    public static func connect(
        config: ConnectionConfig
    ) async throws -> SSHClient {
        switch config.authMethod {
        case .none:
            return try await SSHClient.connect(
                host: config.host,
                port: config.port,
                user: config.user,
            )
        case .password(let password):
            return try await SSHClient.connect(
                host: config.host,
                port: config.port,
                user: config.user,
                password: password,
            )
        case .privateKey(let base64PrivateKey, let passphrase):
            return try await SSHClient.connect(
                host: config.host,
                port: config.port,
                user: config.user,
                base64PrivateKey: base64PrivateKey,
                passphrase: passphrase,
            )
        }
    }

    @discardableResult
    public static func withSession<T: Sendable>(
        config: ConnectionConfig,
        perform: @Sendable (SSHClient, SFTPClient) async throws -> T
    ) async throws -> T {
        let sshClient = try await connect(config: config)
        do {
            let result = try await sshClient.withSftp { sftpClient in
                try await perform(sshClient, sftpClient)
            }
            await sshClient.close()
            return result
        } catch {
            await sshClient.close()
            throw error
        }
    }
}
