import Common
import FileProvider
import SwiftLibSSH

class Session {
    let name: String
    let config: ConnectionConfig
    let ssh: SSHClient
    let sftp: SFTPClient
    let itemManager: ItemManager

    private let logger: Logger

    init(
        name: String,
        config: ConnectionConfig,
        ssh: SSHClient,
        sftp: SFTPClient,
        itemManager: ItemManager
    ) {
        self.name = name
        self.config = config
        self.ssh = ssh
        self.sftp = sftp
        self.itemManager = itemManager

        self.logger = Logger(category: "\(name):Session")
    }

    func path(for identifier: NSFileProviderItemIdentifier) async -> String {
        let relative = await itemManager.path(for: identifier)
        return config.path(for: relative)
    }

    func item(
        for identifier: NSFileProviderItemIdentifier,
    ) async throws -> Item {
        try await Item(
            domainName: name,
            itemIdentifier: identifier,
            itemAttributes: attributes(for: identifier),
            itemManager: itemManager
        )
    }

    func attributes(
        for identifier: NSFileProviderItemIdentifier
    ) async throws -> SFTPAttributes {
        try await mapError(with: identifier) {
            try await sftp.attributes(atPath: await path(for: identifier))
        }
    }

    func exists(for identifier: NSFileProviderItemIdentifier) async -> Bool {
        do {
            _ = try await sftp.attributes(atPath: await path(for: identifier))
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
        logger.info(
            "Set attributes of \(identifier.desc): \(changes.joined(separator: ", "))"
        )
        try await mapError(with: identifier) {
            try await sftp.setAttributes(
                atPath: await path(for: identifier),
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
        from old: NSFileProviderItemIdentifier,
        to new: NSFileProviderItemIdentifier,
        ifParentNotExists: OnParentNotExists = .fail
    ) async throws {
        logger.info("Move \(old.desc) to \(new.desc)")
        try await mapError {
            do {
                try await sftp.move(from: await path(for: old), to: await path(for: new))
            } catch SSHError.sftpError(.noSuchFile, _)
                where ifParentNotExists == .create
            {
                logger.info("Parent of \(new.desc) doesn't exist")
                try await createDirectory(for: await itemManager.parent(for: new), ifExists: .succeed)
                try await sftp.move(from: await path(for: old), to: await path(for: new))
            }
        }
    }

    func removeFile(
        for identifier: NSFileProviderItemIdentifier
    ) async throws {
        logger.info("Remove \(identifier.desc)")
        try await mapError(with: identifier) {
            try await sftp.removeFile(atPath: await path(for: identifier))
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
        logger.info(
            "Create directory \(identifier.desc) with permissions \(String(mode, radix: 8))"
        )
        try await mapError(with: identifier) {
            do {
                try await sftp.createDirectory(
                    atPath: await path(for: identifier),
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
        logger.info("Remove directory \(identifier.desc)")
        try await mapError(with: identifier) {
            try await sftp.removeDirectoryRecursively(
                atPath: await path(for: identifier)
            )
        }
    }

    func withFile<T: Sendable>(
        for identifier: NSFileProviderItemIdentifier,
        accessType: AccessType,
        mode: mode_t = 0o600,
        perform: @Sendable (SFTPFile) async throws -> T
    ) async throws -> T {
        try await mapError(with: identifier) {
            try await sftp.withSftpFile(
                atPath: await path(for: identifier),
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
        try await mapError(with: identifier) {
            try await sftp.withDirectory(
                atPath: await path(for: identifier),
                perform: perform
            )
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
            logger.debug("\(identifier.desc) doesn't exist")
            throw NSError.fileProviderErrorForNonExistentItem(
                withIdentifier: identifier
            )
        } catch SSHError.sftpError(.fileAlreadyExists, _) {
            logger.debug("\(identifier.desc) already exists")
            throw NSFileProviderError(.filenameCollision)
        }
    }
}