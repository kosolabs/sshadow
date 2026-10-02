import Common
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "SwiftLibSSH")

extension SSHClient {
    static func connect(
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
            logger.notice("SSH config connected: \(config)")
            return (ssh, sftp)
        } catch {
            logger.error("Failed to connect SSH config \(config): \(error)")
            throw ConnectionError(from: error)
        }
    }
}

extension SFTPClient {
    func makeDirectory(
        at path: String,
        mode: mode_t,
        ifExists: OnExists = .fail
    ) async throws {
        do {
            try await createDirectory(at: path, mode: mode)
        } catch let error
            where error.sftpError == .failure
            || error.sftpError == .fileAlreadyExists
        {
            guard let existing = await existing(at: path) else { throw error }
            if ifExists == .succeed, existing.type == .directory { return }
            throw collision(with: existing, at: path)
        }
    }

    func makeSymlink(to target: String, at path: String) async throws {
        do {
            try await createSymlink(to: target, at: path)
        } catch let error where error.sftpError == .failure {
            guard let existing = await existing(at: path) else { throw error }
            throw collision(with: existing, at: path)
        }
    }

    func writeFile<T: Sendable>(
        at path: String,
        mode: mode_t,
        perform: @Sendable (SFTPFile) async throws -> T
    ) async throws -> T {
        do {
            return try await withSftpFile(
                at: path,
                accessType: .writeOnly,
                mode: mode,
                perform: perform
            )
        } catch let error as SSHError where error.sftpError == .failure {
            guard let existing = await existing(at: path),
                existing.type == .directory
            else { throw error }
            throw collision(with: existing, at: path)
        }
    }

    private func existing(at path: String) async -> SFTPAttributes? {
        try? await attributes(at: path, followSymlinks: false)
    }

    private func collision(
        with existing: SFTPAttributes,
        at path: String
    ) -> SSHError {
        .sftpError(
            .fileAlreadyExists,
            message: "\(existing.type) already exists at \(path)"
        )
    }
}

extension SFTPAttributes {
    var itemSize: UInt64? {
        type == .directory ? nil : size
    }
}
