import Common
import FileProvider
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "Session")

class Session {
    let config: ConnectionConfig
    let ssh: SSHClient
    let sftp: SFTPClient
    let db: DomainDB

    init(
        config: ConnectionConfig,
        ssh: SSHClient,
        sftp: SFTPClient,
        db: DomainDB
    ) {
        self.config = config
        self.ssh = ssh
        self.sftp = sftp
        self.db = db
    }

    func close() async {
        await sftp.close()
        await ssh.close()
        logger.info("Closed: \(config.url)")
    }

    func id(of itemId: NSFileProviderItemIdentifier) async -> String {
        await "FPItemID(\(itemId.desc), \(db.path(for: itemId)))"
    }

    func name(
        of itemId: NSFileProviderItemIdentifier
    ) async throws -> String {
        try await db.name(of: itemId)
    }

    func child(
        of parentId: NSFileProviderItemIdentifier = .rootContainer,
        path: String,
        ifNotExists: DomainDB.OnNotExists = .create
    ) async throws -> NSFileProviderItemIdentifier {
        try await db.child(of: parentId, path: path, ifNotExists: ifNotExists)
    }

    func parent(
        of itemId: NSFileProviderItemIdentifier
    ) async throws -> NSFileProviderItemIdentifier {
        try await db.parent(of: itemId)
    }

    func path(
        for itemId: NSFileProviderItemIdentifier
    ) async -> String {
        await config.path(for: db.path(for: itemId))
    }

    func path(
        for name: String,
        parentId: NSFileProviderItemIdentifier
    ) async -> String {
        await config.path(for: db.path(for: name, in: parentId))
    }

    func attributes(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> SFTPAttributes {
        try await mapError(with: itemId) {
            try await sftp.attributes(atPath: path(for: itemId))
        }
    }

    func mapError<T>(
        with itemId: NSFileProviderItemIdentifier,
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch SSHError.sftpError(.noSuchFile, _) {
            await logger.debug("\(id(of: itemId)) doesn't exist")
            throw NSError.fileProviderErrorForNonExistentItem(
                withIdentifier: itemId
            )
        } catch SSHError.sftpError(.fileAlreadyExists, _) {
            await logger.debug("\(id(of: itemId)) already exists")
            throw NSFileProviderError(.filenameCollision)
        }
    }
}
