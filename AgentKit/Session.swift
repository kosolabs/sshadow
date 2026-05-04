import Common
import FileProvider
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "Session")

private actor ChunkCache {
    private var cached: [String: Set<UInt64>] = [:]

    func contains(_ index: UInt64, for itemId: NSFileProviderItemIdentifier) -> Bool {
        cached[itemId.rawValue]?.contains(index) ?? false
    }

    func record(_ index: UInt64, for itemId: NSFileProviderItemIdentifier) {
        cached[itemId.rawValue, default: []].insert(index)
    }
}

class Session {
    let config: ConnectionConfig
    let ssh: SSHClient
    let sftp: SFTPClient
    let db: DomainDB
    private let chunkCache = ChunkCache()

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
        await "FPItemID(\(itemId.rawValue), \(db.path(for: itemId)))"
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
        let name = try await name(of: itemId)
        let attrs = try await attributes(for: itemId)
        return FileInfo(
            id: itemId.rawValue,
            parentId: parentId.rawValue,
            name: name,
            isDirectory: attrs.type == .directory,
            size: attrs.size,
            permissions: attrs.permissions,
            accessTime: attrs.accessTime,
            modifyTime: attrs.modifyTime,
            createTime: attrs.createTime
        )
    }

    func list(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> [FileInfo] {
        try await withDirectory(for: itemId) { dir in
            var entries: [FileInfo] = []
            for try await attrs in dir {
                if let name = attrs.name {
                    let childId = try await self.child(
                        of: itemId,
                        path: name
                    )
                    entries.append(
                        FileInfo(
                            id: childId.rawValue,
                            parentId: itemId.rawValue,
                            name: name,
                            isDirectory: attrs.type == .directory,
                            size: attrs.size,
                            permissions: attrs.permissions,
                            accessTime: attrs.accessTime,
                            modifyTime: attrs.modifyTime,
                            createTime: attrs.createTime
                        )
                    )
                }
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
                logger.info("Directory already exists for \(itemId.rawValue)")
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
        progress.fileOperationKind = .downloading
        progress.totalUnitCount = Int64(size)
        let speedometer = Speedometer(progress: progress)

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
        let itemRef = await id(of: itemId)
        let url = SSHadow.groupUrl.appending(path: itemId.rawValue)
        logger.info("Download \(itemRef) into \(url)")

        try create(file: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let info = try await info(for: itemId)

        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.totalUnitCount = Int64(info.size)
        let speedometer = Speedometer(progress: progress)

        let bufferSize = sftp.limits.readLength(for: chunkSize)
        try await withFile(for: itemId, accessType: .readOnly) { file in
            for try await data in file.stream(bufferSize: bufferSize) {
                if progress.isCancelled {
                    logger.info("Download \(itemRef) cancelled")
                    throw AgentError.userCancelled
                }
                try handle.write(contentsOf: data)
                if let progress = speedometer.update(delta: data.count) {
                    logger.debug("Downloading \(itemRef): \(progress)")
                }
            }
        }

        logger.info("Downloaded \(itemRef): \(speedometer.finalize())")
        return (url, info)
    }

    func cache(
        chunkIndex: UInt64,
        itemId: NSFileProviderItemIdentifier,
        fileSize: UInt64
    ) async throws {
        let itemRef = await id(of: itemId)
        let chunkId = "\(itemRef)[\(chunkIndex)]"
        let bytes = FileChunk.byteRange(for: chunkIndex, fileSize: fileSize)
        guard !bytes.isEmpty else { return }

        if await chunkCache.contains(chunkIndex, for: itemId) {
            logger.debug("Cache hit \(chunkId)")
            return
        }

        let url = SSHadow.groupUrl.appending(path: itemId.rawValue)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: bytes.offset)
        try await withFile(for: itemId, accessType: .readOnly) { file in
            for try await data in file.stream(
                offset: bytes.offset,
                length: bytes.length
            ) {
                try handle.write(contentsOf: data)
            }
        }

        await chunkCache.record(chunkIndex, for: itemId)
        logger.debug("Cached \(chunkId)")
    }

    func stream(
        itemId: NSFileProviderItemIdentifier,
        range: Range<UInt64>,
        progress: Progress
    ) async throws -> (URL, Range<UInt64>) {
        let itemRef = await id(of: itemId)
        let url = SSHadow.groupUrl.appending(path: itemId.rawValue)
        let chunkRange = FileChunk.chunkRange(for: range)
        let info = try await info(for: itemId)
        let byteRange = FileChunk.byteRange(for: chunkRange, fileSize: info.size)
        let rangeId = "\(itemRef)(\(range))[\(chunkRange)->\(byteRange)]"
        logger.info("Stream \(rangeId) into \(url)")

        try create(file: url)

        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.totalUnitCount = Int64(byteRange.length)
        let speedometer = Speedometer(progress: progress)

        for chunkIndex in chunkRange {
            let bytes = FileChunk.byteRange(for: chunkIndex, fileSize: info.size)
            try await cache(chunkIndex: chunkIndex, itemId: itemId, fileSize: info.size)
            speedometer.update(delta: bytes.count)
        }

        logger.info("Streamed \(rangeId): \(speedometer.finalize())")
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
            throw AgentError.itemNotFound(itemId.rawValue)
        } catch SSHError.sftpError(.fileAlreadyExists, _) {
            await logger.debug("\(id(of: itemId)) already exists")
            throw AgentError.filenameCollision
        }
    }
}
