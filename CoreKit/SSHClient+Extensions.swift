import Common
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "SSHClient")

extension SSHClient {
    public static func connect(
        config: ConnectionConfig
    ) async throws(ConnectionError) -> (SSHClient, SFTPClient) {
        do {
            let ssh =
                switch config.authMethod {
                case .none:
                    try await SSHClient.connect(
                        host: config.host,
                        port: config.port,
                        user: config.user
                    )
                case .password(let password):
                    try await SSHClient.connect(
                        host: config.host,
                        port: config.port,
                        user: config.user,
                        auth: .password(password)
                    )
                case .privateKey(let contents, let passphrase):
                    try await SSHClient.connect(
                        host: config.host,
                        port: config.port,
                        user: config.user,
                        auth: .privateKey(
                            contents: contents,
                            passphrase: passphrase
                        )
                    )
                }
            let sftp = try await ssh.sftp()
            let attrs = try await sftp.attributes(at: config.path())
            if attrs.type != .directory {
                throw ConnectionError.remotePathNotDirectory
            }
            logger.info("SSH config connected: \(config)")
            return (ssh, sftp)
        } catch {
            logger.error("Failed to connect SSH config \(config): \(error)")
            throw ConnectionError(from: error)
        }
    }
}
