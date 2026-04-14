import Common
import FileProvider
import SwiftLibSSH

class Session {
    let domain: NSFileProviderDomain
    let config: ConnectionConfig
    let ssh: SSHClient
    let sftp: SFTPClient
    let db: SSHadowDB

    var name: String {
        domain.displayName
    }

    private let logger: Logger

    init(
        domain: NSFileProviderDomain,
        config: ConnectionConfig,
        ssh: SSHClient,
        sftp: SFTPClient,
        db: SSHadowDB
    ) {
        self.domain = domain
        self.config = config
        self.ssh = ssh
        self.sftp = sftp
        self.db = db

        self.logger = Logger(category: "\(domain.displayName):Session")
    }

    func id(of identifier: NSFileProviderItemIdentifier) async -> String {
        await "FPItemID(\(identifier.desc), \(db.path(for: identifier)))"
    }

    func name(
        of identifier: NSFileProviderItemIdentifier
    ) async throws -> String {
        try await db.name(of: identifier)
    }

    func child(
        of parent: NSFileProviderItemIdentifier = .rootContainer,
        path: String,
        ifNotExists: SSHadowDB.OnNotExists = .create
    ) async throws -> NSFileProviderItemIdentifier {
        try await db.child(of: parent, path: path, ifNotExists: ifNotExists)
    }

    func parent(
        of identifier: NSFileProviderItemIdentifier
    ) async throws -> NSFileProviderItemIdentifier {
        try await db.parent(of: identifier)
    }

    func path(
        for identifier: NSFileProviderItemIdentifier
    ) async -> String {
        await config.path(for: db.path(for: identifier))
    }
    
    func path(
        for name: String,
        parentId: NSFileProviderItemIdentifier
    ) async -> String {
        await config.path(for: db.path(for: name, in: parentId))
    }

    func cacheFileURL(
        for identifier: NSFileProviderItemIdentifier
    ) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "chunks-\(identifier.rawValue)")
    }

    func item(
        for identifier: NSFileProviderItemIdentifier,
    ) async throws -> Item {
        try await Item(
            domainName: domain.displayName,
            itemIdentifier: identifier,
            parentItemIdentifier: parent(of: identifier),
            filename: name(of: identifier),
            itemAttributes: attributes(for: identifier)
        )
    }

    func attributes(
        for identifier: NSFileProviderItemIdentifier
    ) async throws -> SFTPAttributes {
        try await mapError(with: identifier) {
            try await sftp.attributes(atPath: path(for: identifier))
        }
    }

    func exists(for identifier: NSFileProviderItemIdentifier) async -> Bool {
        do {
            _ = try await sftp.attributes(atPath: path(for: identifier))
            return true
        } catch {
            return false
        }
    }

    func setAttributes(
        for identifier: NSFileProviderItemIdentifier,
        permissions: mode_t? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil,
    ) async throws {
        var changes: [String] = []
        if let accessTime = accessTime {
            changes.append("accessTime: \(accessTime)")
        }
        if let modifyTime = modifyTime {
            changes.append("modifyTime: \(modifyTime)")
        }
        if let permissions = permissions {
            changes.append("permissions: \(String(permissions, radix: 8))")
        }
        await logger.info(
            "Set attributes of \(id(of: identifier)): \(changes.joined(separator: ", "))"
        )
        try await mapError(with: identifier) {
            try await sftp.setAttributes(
                atPath: path(for: identifier),
                permissions: permissions,
                accessTime: accessTime,
                modifyTime: modifyTime
            )
        }
    }

    enum OnParentNotExists {
        case fail
        case create
    }

    func move(
        _ id: NSFileProviderItemIdentifier,
        toParent newParentId: NSFileProviderItemIdentifier,
        name newName: String,
        ifParentNotExists: OnParentNotExists = .fail
    ) async throws {
        let oldPath = await path(for: id)
        let newPath = await path(for: newName, parentId: newParentId)

        await logger.info("Move \(self.id(of: id)) to \(newPath)")
        try await mapError {
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

        try await db.move(id, toParent: newParentId, name: newName)
    }

    func removeFile(
        for identifier: NSFileProviderItemIdentifier
    ) async throws {
        await logger.info("Remove \(id(of: identifier))")
        try await mapError(with: identifier) {
            try await sftp.removeFile(atPath: path(for: identifier))
        }
    }

    enum OnExists {
        case fail
        case succeed
    }

    func createDirectory(
        for identifier: NSFileProviderItemIdentifier,
        mode: mode_t = 0o700,
        ifExists: OnExists = .fail
    ) async throws {
        await logger.info(
            "Create directory \(id(of: identifier)) with permissions \(String(mode, radix: 8))"
        )
        try await mapError(with: identifier) {
            do {
                try await sftp.createDirectory(
                    atPath: path(for: identifier),
                    mode: mode
                )
            } catch SSHError.sftpError(.fileAlreadyExists, _)
                where ifExists == .succeed
            {
                logger.info("Directory already exists for \(identifier.desc)")
            }
        }
    }

    func removeDirectory(
        for identifier: NSFileProviderItemIdentifier
    ) async throws {
        await logger.info("Remove directory \(id(of: identifier))")
        try await mapError(with: identifier) {
            try await sftp.removeDirectoryRecursively(
                atPath: path(for: identifier)
            )
        }
    }

    func withFile<T: Sendable>(
        for identifier: NSFileProviderItemIdentifier,
        accessType: AccessType,
        mode: mode_t = 0o600,
        perform: @Sendable (SFTPFile) async throws -> T
    ) async throws -> T {
        await logger.info("With \(accessType) file \(id(of: identifier))")
        return try await mapError(with: identifier) {
            try await sftp.withSftpFile(
                atPath: path(for: identifier),
                accessType: accessType,
                mode: mode,
                perform: perform
            )
        }
    }

    func withDirectory<T: Sendable>(
        for identifier: NSFileProviderItemIdentifier,
        perform: @Sendable (SFTPDirectory) async throws -> T
    ) async throws -> T {
        await logger.info("With directory \(id(of: identifier))")
        return try await mapError(with: identifier) {
            try await sftp.withDirectory(
                atPath: path(for: identifier),
                perform: perform
            )
        }
    }

    func enumerateItems(
        for identifier: NSFileProviderItemIdentifier,
        yield: @Sendable ([any NSFileProviderItemProtocol]) -> Void
    ) async throws {
        try await withDirectory(for: identifier) { dir in
            for try await attrs in dir {
                if let name = attrs.name {
                    let childId = try await child(
                        of: identifier,
                        path: name
                    )
                    let item = Item(
                        domainName: self.name,
                        itemIdentifier: childId,
                        parentItemIdentifier: identifier,
                        filename: name,
                        itemAttributes: attrs
                    )
                    yield([item])
                }
            }
        }
    }

    func mapError<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch SSHError.sftpError(.noSuchFile, _) {
            logger.fault("No such file")
            throw NSFileProviderError(.noSuchItem)
        } catch SSHError.sftpError(.fileAlreadyExists, _) {
            logger.fault("File already exists")
            throw NSFileProviderError(.filenameCollision)
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
