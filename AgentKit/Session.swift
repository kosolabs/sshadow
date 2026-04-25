import Common
import FileProvider
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "Session")

class Session {
    let profile: ConnectionProfile
    let ssh: SSHClient
    let sftp: SFTPClient
    let db: DomainDB

    init(
        profile: ConnectionProfile,
        ssh: SSHClient,
        sftp: SFTPClient,
        db: DomainDB
    ) {
        self.profile = profile
        self.ssh = ssh
        self.sftp = sftp
        self.db = db
    }

    func id(of identifier: NSFileProviderItemIdentifier) async -> String {
        await "FPItemID(\(identifier.desc), \(db.path(for: identifier)))"
    }

    func close() async {
        await sftp.close()
        await ssh.close()
        logger.info("Closed: \(profile.url)")
    }

    func path(for id: NSFileProviderItemIdentifier) async -> String {
        await profile.path(for: db.path(for: id))
    }

    func attributes(
        for id: NSFileProviderItemIdentifier
    ) async throws -> SFTPAttributes {
        try await mapError(with: id) {
            try await sftp.attributes(atPath: path(for: id))
        }
    }

    func mapError<T>(
        with identifier: NSFileProviderItemIdentifier,
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch SSHError.sftpError(.noSuchFile, _) {
            await logger.debug("\(id(of: identifier)) doesn't exist")
            throw NSError.fileProviderErrorForNonExistentItem(
                withIdentifier: identifier
            )
        } catch SSHError.sftpError(.fileAlreadyExists, _) {
            await logger.debug("\(id(of: identifier)) already exists")
            throw NSFileProviderError(.filenameCollision)
        }
    }
}
