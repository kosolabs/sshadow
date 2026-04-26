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

    func setAttributes(
        for itemId: NSFileProviderItemIdentifier,
        permissions: mode_t? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil
    ) async throws {
        var changes: [String] = []
        if let accessTime { changes.append("accessTime: \(accessTime)") }
        if let modifyTime { changes.append("modifyTime: \(modifyTime)") }
        if let permissions {
            changes.append("permissions: \(String(permissions, radix: 8))")
        }
        await logger.info(
            "Set attributes of \(id(of: itemId)): \(changes.joined(separator: ", "))"
        )
        try await mapError(with: itemId) {
            try await sftp.setAttributes(
                atPath: path(for: itemId),
                permissions: permissions,
                accessTime: accessTime,
                modifyTime: modifyTime
            )
        }
    }

    func createDirectory(
        for itemId: NSFileProviderItemIdentifier,
        mode: mode_t = 0o700,
        ifExists: OnExists = .fail
    ) async throws {
        await logger.info(
            "Create directory \(id(of: itemId)) with permissions \(String(mode, radix: 8))"
        )
        try await mapError(with: itemId) {
            do {
                try await sftp.createDirectory(
                    atPath: path(for: itemId),
                    mode: mode
                )
            } catch SSHError.sftpError(.fileAlreadyExists, _)
                where ifExists == .succeed
            {
                logger.info("Directory already exists for \(itemId.desc)")
            }
        }
    }

    func move(
        _ itemId: NSFileProviderItemIdentifier,
        toParent newParentId: NSFileProviderItemIdentifier,
        name newName: String,
        ifParentNotExists: OnParentNotExists = .fail
    ) async throws {
        let oldPath = await path(for: itemId)
        let newPath = await path(for: newName, parentId: newParentId)

        await logger.info("Move \(id(of: itemId)) to \(newPath)")
        try await mapError(with: itemId) {
            do {
                try await sftp.move(from: oldPath, to: newPath)
            } catch SSHError.sftpError(.noSuchFile, _)
                where ifParentNotExists == .create
            {
                logger.info("Parent doesn't exist, creating")
                try await sftp.createDirectory(
                    atPath: await path(for: newParentId),
                    mode: 0o700
                )
                try await sftp.move(from: oldPath, to: newPath)
            }
        }

        try await db.move(itemId, toParent: newParentId, name: newName)
    }

    func removeFile(
        for itemId: NSFileProviderItemIdentifier
    ) async throws {
        await logger.info("Remove \(id(of: itemId))")
        try await mapError(with: itemId) {
            try await sftp.removeFile(atPath: path(for: itemId))
        }
    }

    func removeDirectory(
        for itemId: NSFileProviderItemIdentifier
    ) async throws {
        await logger.info("Remove directory \(id(of: itemId))")
        try await mapError(with: itemId) {
            try await sftp.removeDirectoryRecursively(
                atPath: path(for: itemId)
            )
        }
    }

    func download(
        itemId: NSFileProviderItemIdentifier,
        progress: Progress,
    ) async throws -> (URL, SFTPAttributes) {
        let itemRef = await id(of: itemId)
        let url = SSHadow.groupUrl.appending(path: itemId.rawValue)
        guard FileManager.default.createFile(atPath: url.path(), contents: nil)
        else { throw NSFileProviderError(.insufficientQuota) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let attributes = try await attributes(for: itemId)
        logger.info("Download \(itemRef) into \(url.path())")

        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.totalUnitCount = Int64(attributes.size)
        let speedometer = Speedometer(progress: progress)

        try await withFile(for: itemId, accessType: .readOnly) { file in
            for try await data in file.stream() {
                if progress.isCancelled {
                    throw CocoaError(.userCancelled)
                }
                try handle.write(contentsOf: data)
                if let progress = speedometer.update(delta: data.count) {
                    logger.debug("Downloading \(itemRef): \(progress)")
                }
            }
        }
        
        logger.info("Downloaded \(itemRef): \(speedometer.finalize())")
        return (url, attributes)
    }

    func withFile<T: Sendable>(
        for itemId: NSFileProviderItemIdentifier,
        accessType: AccessType,
        mode: mode_t = 0o600,
        perform: @Sendable (SFTPFile) async throws -> T
    ) async throws -> T {
        await logger.info("With \(accessType) file \(id(of: itemId))")
        return try await mapError(with: itemId) {
            try await sftp.withSftpFile(
                atPath: path(for: itemId),
                accessType: accessType,
                mode: mode,
                perform: perform
            )
        }
    }

    func withDirectory<T: Sendable>(
        for itemId: NSFileProviderItemIdentifier,
        perform: @Sendable (SFTPDirectory) async throws -> T
    ) async throws -> T {
        await logger.info("With directory \(id(of: itemId))")
        return try await mapError(with: itemId) {
            try await sftp.withDirectory(
                atPath: path(for: itemId),
                perform: perform
            )
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
