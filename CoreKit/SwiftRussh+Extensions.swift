import Common
import Foundation
import SwiftRussh

private let logger = Logger(category: "SwiftRussh")

extension SSHClient {
    static func serverHostKey(
        host: String,
        port: UInt16
    ) async throws(ConnectionError) -> SSHHostKey {
        do {
            return try await SSHClient.hostKey(host: host, port: port)
        } catch {
            logger.error("Failed to fetch host key for \(host):\(port): \(error)")
            throw ConnectionError(from: error)
        }
    }

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
                        user: config.user,
                        expectedHostKey: config.hostKey
                    )
                case .password(let password):
                    try await SSHClient.connect(
                        host: config.host,
                        port: config.port,
                        user: config.user,
                        auth: .password(password),
                        expectedHostKey: config.hostKey
                    )
                case .privateKey(let contents, let passphrase):
                    try await SSHClient.connect(
                        host: config.host,
                        port: config.port,
                        user: config.user,
                        auth: .privateKey(
                            contents: contents,
                            passphrase: passphrase
                        ),
                        expectedHostKey: config.hostKey
                    )
                }
            let sftp = try await ssh.sftp()
            let path = config.path()
            guard let attrs = try await sftp.attributesIfExists(at: path) else {
                throw ConnectionError.remotePathNotFound
            }
            guard attrs.type == .directory else {
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
    func makeDirectory(at path: String, mode: mode_t) async throws {
        do {
            try await createDirectory(at: path, permissions: mode)
        } catch let error as SSHError
            where error.sftpStatus == .failure
            || error.sftpStatus == .fileAlreadyExists
        {
            guard let existing = try await attributesIfExists(at: path) else {
                throw error
            }
            throw collision(with: existing, at: path)
        }
    }

    func makeSymlink(to target: String, at path: String) async throws {
        do {
            try await createSymlink(to: target, at: path)
        } catch let error as SSHError where error.sftpStatus == .failure {
            guard let existing = try await attributesIfExists(at: path) else {
                throw error
            }
            throw collision(with: existing, at: path)
        }
    }

    func writeFile<T: Sendable>(
        at path: String,
        mode: mode_t,
        perform: @Sendable (SFTPFile) async throws -> T
    ) async throws -> T {
        do {
            return try await withFile(
                at: path,
                access: .writeOnly,
                options: [.create, .truncate],
                permissions: mode,
                perform: perform
            )
        } catch let error as SSHError where error.sftpStatus == .failure {
            guard let existing = try await attributesIfExists(at: path),
                existing.type == .directory
            else { throw error }
            throw collision(with: existing, at: path)
        }
    }

    func moveWithoutReplacing(
        from source: String,
        to path: String
    ) async throws {
        if let existing = try await attributesIfExists(at: path) {
            throw collision(with: existing, at: path)
        }
        try await move(from: source, to: path)
    }

    func attributesIfExists(at path: String) async throws -> SFTPAttributes? {
        do {
            let attrs = try await attributes(
                at: path,
                followSymlinks: false
            )
            return attrs
        } catch SSHError.sftp(.noSuchFile, _) {
            return nil
        }
    }

    func isDirectory(at path: String) async throws -> Bool {
        try await attributesIfExists(at: path)?.type == .directory
    }

    private func collision(
        with existing: SFTPAttributes,
        at path: String
    ) -> SSHError {
        .sftp(
            .fileAlreadyExists,
            message: "\(existing.type) already exists at \(path)"
        )
    }
}

extension SFTPAttributes {
    var itemSize: UInt64? {
        type == .directory ? nil : size
    }

    var ignoreFileVersion: IgnoreFile.Version {
        IgnoreFile.Version(
            modifyTime: modifyTime ?? Date(timeIntervalSince1970: 0),
            size: size ?? 0
        )
    }
}
