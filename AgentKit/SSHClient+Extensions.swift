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

    public static func test(config: ConnectionConfig) async throws {
        do {
            try await SSHClient.withSession(config: config) { _, sftp in
                logger.debug("SFTP Limits for \(config.socket): \(sftp.limits)")
                let attrs = try await sftp.attributes(
                    at: config.path == "" ? "." : config.path
                )
                if attrs.type != .directory {
                    throw InitDomainError.pathNotADirectory
                }
            }
        } catch SSHError.connectionFailed(let message)
            where message.contains("Failed to resolve hostname")
        {
            logger.info("Unknown host: \(message)")
            throw InitDomainError.unknownHost
        } catch SSHError.connectionFailed(let message)
            where message.contains("Connection refused")
            || message.contains("Socket error")
            || message.contains("Bad file descriptor")
        {
            logger.info("Connection refused: \(message)")
            throw InitDomainError.connectionRefused
        } catch SSHError.connectionFailed(let message)
            where message.contains("Timeout")
        {
            logger.info("Connection timeout: \(message)")
            throw InitDomainError.timeout
        } catch SSHError.authenticationFailed(let message)
            where message.contains("Failed to import private key")
        {
            logger.info("Invalid private key")
            throw InitDomainError.invalidPrivateKey
        } catch SSHError.authenticationFailed(let message) {
            logger.info("Authentication failed: \(message)")
            throw InitDomainError.userauthPasswordFailed
        } catch SSHError.sftpError(.noSuchFile, let path) {
            logger.info("No such file: \(path)")
            throw InitDomainError.pathNotFound
        }
    }
}
