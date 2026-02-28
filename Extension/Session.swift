import Common
import FileProvider
import SwiftLibSSH

struct Session {
    let name: String
    let config: ConnectionConfig
    let ssh: SSHClient
    let sftp: SFTPClient

    func path(for identifier: NSFileProviderItemIdentifier) -> String {
        config.path(for: identifier)
    }

    func item(
        for identifier: NSFileProviderItemIdentifier,
    ) async throws -> Item {
        try await Item(
            domainName: name,
            itemIdentifier: identifier,
            itemAttributes: attributes(for: identifier)
        )
    }

    func attributes(
        for identifier: NSFileProviderItemIdentifier
    ) async throws -> SFTPAttributes {
        try await mapError {
            try await sftp.attributes(atPath: path(for: identifier))
        }
    }

    func setAttributes(
        for identifier: NSFileProviderItemIdentifier,
        size: UInt64? = nil,
        uid: UInt32? = nil,
        gid: UInt32? = nil,
        permissions: mode_t? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil,
    ) async throws {
        try await mapError {
            try await sftp.setAttributes(
                atPath: path(for: identifier),
                size: size,
                uid: uid,
                gid: gid,
                permissions: permissions,
                accessTime: accessTime,
                modifyTime: modifyTime
            )
        }
    }

    func move(
        from old: NSFileProviderItemIdentifier,
        to new: NSFileProviderItemIdentifier
    ) async throws {
        try await mapError {
            try await sftp.move(from: path(for: old), to: path(for: new))
        }
    }

    func removeFile(
        for identifier: NSFileProviderItemIdentifier
    ) async throws {
        try await mapError {
            try await sftp.removeFile(atPath: path(for: identifier))
        }
    }

    func createDirectory(
        for identifier: NSFileProviderItemIdentifier
    ) async throws {
        try await mapError {
            try await sftp.createDirectory(atPath: path(for: identifier))
        }
    }

    func removeDirectory(
        for identifier: NSFileProviderItemIdentifier
    ) async throws {
        try await mapError {
            try await sftp.removeDirectory(atPath: path(for: identifier))
        }
    }

    func withFile<T: Sendable>(
        for identifier: NSFileProviderItemIdentifier,
        accessType: AccessType,
        mode: mode_t = 0,
        perform: @Sendable (SFTPFile) async throws -> T
    ) async throws -> T {
        try await mapError {
            try await sftp.withSftpFile(
                atPath: path(for: identifier),
                accessType: accessType,
                perform: perform
            )
        }
    }

    func mapError<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch SSHError.sftpError(.noSuchFile, _) {
            throw NSFileProviderError(.noSuchItem)
        }
    }
}
