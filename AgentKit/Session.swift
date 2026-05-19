import Common
import FileProvider
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "Session")

class Session {
    private let config: ConnectionConfig
    private let ssh: SSHClient
    private let sftp: SFTPClient
    private let db: DomainDB

    private let pool = FileCachePool()

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
    }

    var url: String {
        config.url
    }

    var limits: SFTPLimits {
        sftp.limits
    }

    func id(of itemId: NSFileProviderItemIdentifier) async -> String {
        await "FPItemID(\(itemId.rawValue), \(path(for: itemId)))"
    }

    func name(
        of itemId: NSFileProviderItemIdentifier
    ) async throws -> String {
        try await db.name(of: itemId)
    }

    func child(
        of parentId: NSFileProviderItemIdentifier = .rootContainer,
        path: String,
        ifNotExists: OnNotExists = .create
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

    func info(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> FileInfo {
        let parentId = try await parent(of: itemId)
        let attrs = try await attributes(for: itemId)
        let name = try await name(of: itemId)

        let type: FileInfo.FileType =
            switch attrs.type {
            case .directory:
                .folder
            case .symlink:
                .symlink(target: try await symlinkTarget(for: itemId))
            default:
                .file
            }

        return FileInfo(
            id: itemId.rawValue,
            parentId: parentId.rawValue,
            name: name,
            type: type,
            size: attrs.size,
            permissions: attrs.permissions,
            accessTime: attrs.accessTime,
            modifyTime: attrs.modifyTime,
            createTime: attrs.createTime
        )
    }

    func list(
        for parentId: NSFileProviderItemIdentifier
    ) async throws -> [FileInfo] {
        try await withDirectory(for: parentId) { dir in
            var entries: [FileInfo] = []
            for try await attrs in dir {
                guard let name = attrs.name else { continue }
                let itemId = try await child(of: parentId, path: name)
                let type: FileInfo.FileType =
                    switch attrs.type {
                    case .directory:
                        .folder
                    case .symlink:
                        .symlink(target: nil)
                    default:
                        .file
                    }
                let info = FileInfo(
                    id: itemId.rawValue,
                    parentId: parentId.rawValue,
                    name: name,
                    type: type,
                    size: attrs.size,
                    permissions: attrs.permissions,
                    accessTime: attrs.accessTime,
                    modifyTime: attrs.modifyTime,
                    createTime: attrs.createTime
                )
                entries.append(info)
            }
            return entries
        }
    }

    func exists(
        for itemId: NSFileProviderItemIdentifier
    ) async -> Bool {
        do {
            _ = try await attributes(for: itemId)
            return true
        } catch {
            return false
        }
    }

    func attributes(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> SFTPAttributes {
        try await mapError(with: itemId) {
            try await sftp.attributes(
                at: path(for: itemId),
                followSymlinks: false
            )
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
                at: path(for: itemId),
                permissions: permissions,
                accessTime: accessTime,
                modifyTime: modifyTime
            )
        }
    }

    func symlinkTarget(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> String {
        try await mapError(with: itemId) {
            try await sftp.symlinkTarget(at: path(for: itemId))
        }
    }

    func createSymlink(
        at itemId: NSFileProviderItemIdentifier,
        to target: String
    ) async throws {
        try await mapError(with: itemId) {
            try await sftp.createSymlink(to: target, at: path(for: itemId))
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
        do {
            try await sftp.createDirectory(at: path(for: itemId), mode: mode)
        } catch SSHError.sftpError(.fileAlreadyExists, _) {
            switch ifExists {
            case .succeed:
                logger.info("Directory already exists for \(itemId.rawValue)")
            case .fail:
                throw AgentError.filenameCollision
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
                    at: path(for: newParentId),
                    mode: 0o700
                )
                try await sftp.move(from: oldPath, to: newPath)
            }
            try await db.move(itemId, toParent: newParentId, name: newName)
        }
    }

    func removeFile(
        for itemId: NSFileProviderItemIdentifier
    ) async throws {
        await logger.info("Remove \(id(of: itemId))")
        try await mapError(with: itemId) {
            try await sftp.removeFile(at: path(for: itemId))
        }
    }

    func removeDirectory(
        for itemId: NSFileProviderItemIdentifier
    ) async throws {
        await logger.info("Remove directory \(id(of: itemId))")
        try await mapError(with: itemId) {
            try await sftp.removeDirectoryRecursively(at: path(for: itemId))
        }
    }

    func upload(
        itemId: NSFileProviderItemIdentifier,
        file url: URL,
        mode: mode_t,
        chunkSize: UInt64 = SFTPLimits.defaultBufferSize,
        progress: Progress,
    ) async throws {
        let itemRef = await id(of: itemId)
        let fp = try FileHandle(forReadingFrom: url)
        defer { try? fp.close() }

        logger.info("Upload \(itemRef) from \(url.path())")
        let size = try FileManager.default.size(of: url)

        progress.kind = .file
        progress.fileOperationKind = .uploading
        let speedometer = Speedometer(
            progress: progress,
            totalUnitCount: Int64(size)
        )

        let bufferSize = sftp.limits.writeLength(for: chunkSize)
        try await withFile(for: itemId, accessType: .writeOnly, mode: mode) {
            file in
            try await file.withAsyncWriter { writer in
                while let data = try fp.read(upToCount: Int(bufferSize)) {
                    if progress.isCancelled {
                        logger.info("Upload \(itemRef) cancelled")
                        throw AgentError.userCancelled
                    }
                    try await writer.write(data: data)
                    if let progress = speedometer.update(delta: data.count) {
                        logger.debug("Uploading \(itemRef): \(progress)")
                    }
                }
            }
        }

        logger.info("Uploaded \(itemRef): \(speedometer.finalize())")
    }

    private func create(file url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path()) {
            try Data().write(to: url)
        }
    }

    func download(
        itemId: NSFileProviderItemIdentifier,
        chunkSize: UInt64 = SFTPLimits.defaultBufferSize,
        progress: Progress,
    ) async throws -> (URL, FileInfo) {
        let file = try await File(info: info(for: itemId))
        let url = SSHadow.groupUrl.appending(path: itemId.rawValue)
        logger.info("Download \(file) into \(url)")

        try create(file: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        progress.kind = .file
        progress.fileOperationKind = .downloading
        let speedometer = Speedometer(
            progress: progress,
            totalUnitCount: Int64(file.info.size ?? 0)
        )

        let bufferSize = sftp.limits.readLength(for: chunkSize)
        try await withFile(for: itemId, accessType: .readOnly) { fp in
            for try await data in fp.stream(bufferSize: bufferSize) {
                if progress.isCancelled {
                    logger.info("Download \(file) cancelled")
                    throw AgentError.userCancelled
                }
                try handle.write(contentsOf: data)
                if let progress = speedometer.update(delta: data.count) {
                    logger.debug("Downloading \(file): \(progress)")
                }
            }
        }

        logger.info("Downloaded \(file): \(speedometer.finalize())")
        return (url, file.info)
    }

    private func cache(for file: File) async -> FileCache {
        await pool.cache(for: file) { [sftp] itemId, range in
            try await sftp.withSftpFile(
                at: self.path(for: itemId),
                accessType: .readOnly
            ) { file in
                try await file.read(range: range)
            }
        }
    }

    func stream(
        itemId: NSFileProviderItemIdentifier,
        range: Range<UInt64>,
        progress: Progress
    ) async throws -> (URL, Range<UInt64>) {
        let file = try await File(info: info(for: itemId))
        let cache = await cache(for: file)
        let url = SSHadow.groupUrl.appending(path: "\(itemId.rawValue)")
        logger.info("Stream \(file) into \(url)")

        let chunkRange = file.chunkRange(for: range)
        let byteRange = file.byteRange(for: chunkRange)

        try create(file: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        progress.kind = .file
        progress.fileOperationKind = .downloading
        let speedometer = Speedometer(
            progress: progress,
            totalUnitCount: Int64(byteRange.length)
        )

        for chunkIndex in chunkRange {
            let data = try await cache.fetch(chunkId: chunkIndex)
            try handle.seek(toOffset: file.byteOffset(for: chunkIndex))
            try handle.write(contentsOf: data)
            speedometer.update(delta: data.count)
        }

        let prefetchRange = chunkRange.upperBound..<chunkRange.upperBound + 2
        if !prefetchRange.isEmpty {
            Task {
                for chunkIndex in prefetchRange {
                    try await cache.fetch(chunkId: chunkIndex)
                }
            }
        }

        logger.info("Streamed \(file): \(speedometer.finalize())")
        return (url, byteRange)
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
                at: path(for: itemId),
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
                at: path(for: itemId),
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
            throw AgentError.itemNotFound(itemId.rawValue)
        } catch SSHError.sftpError(.permissionDenied, _) {
            throw AgentError.permissionDenied
        } catch SSHError.sftpError(.fileAlreadyExists, _) {
            throw AgentError.filenameCollision
        }
    }
}
