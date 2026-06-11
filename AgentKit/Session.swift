import Common
import FileProvider
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "Session")

class Session {
    private let config: ConnectionConfig
    private let ssh: SSHClient
    private let sftp: SFTPClient
    let db: DomainDB
    private let sharedUrl: URL

    private let cache: FileCache

    init(
        config: ConnectionConfig,
        ssh: SSHClient,
        sftp: SFTPClient,
        db: DomainDB,
        sharedUrl: URL = SSHadow.groupUrl
    ) {
        self.config = config
        self.ssh = ssh
        self.sftp = sftp
        self.db = db
        self.sharedUrl = sharedUrl
        self.cache = FileCache { itemId, range in
            let path = try await config.path(for: db.path(for: itemId))
            return try await sftp.withSftpFile(
                at: path,
                accessType: .readOnly
            ) { file in
                try await file.read(range: range)
            }
        }
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

    func id(of itemId: NSFileProviderItemIdentifier) async throws -> String {
        try await "FPItemID(\(itemId.rawValue), \(path(for: itemId)))"
    }

    func name(
        of itemId: NSFileProviderItemIdentifier
    ) async throws -> String {
        try await db.name(of: itemId)
    }

    func child(
        of parentId: NSFileProviderItemIdentifier = .rootContainer,
        name: String
    ) async throws -> NSFileProviderItemIdentifier {
        try await db.child(of: parentId, name: name).id
    }

    func parent(
        of itemId: NSFileProviderItemIdentifier
    ) async throws -> NSFileProviderItemIdentifier {
        try await db.parent(of: itemId).id
    }

    func path(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> String {
        try await config.path(for: db.path(for: itemId))
    }

    func path(
        for name: String,
        parentId: NSFileProviderItemIdentifier
    ) async throws -> String {
        try await config.path(for: db.path(for: name, in: parentId))
    }

    func item(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> Item {
        return try await db.item(for: itemId)
    }

    func list(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> [Item] {
        if try await !db.isEnumerated(itemId) {
            try await enumerate(itemId: itemId)
        }
        return try await db.children(of: itemId)
    }

    @discardableResult
    func upsert(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        attrs: SFTPAttributes
    ) async throws -> Item {
        let kind: ItemModel.Kind =
            switch attrs.type {
            case .directory:
                .folder
            case .symlink:
                .symlink(
                    target: try await symlinkTarget(
                        for: name,
                        parentId: parentId
                    )
                )
            default:
                .file
            }

        return try await db.upsert(
            parentId: parentId,
            name: name,
            kind: kind,
            size: attrs.size,
            permissions: attrs.permissions,
            accessTime: attrs.accessTime,
            modifyTime: attrs.modifyTime,
            createTime: attrs.createTime
        )
    }

    func reconcile(folder: Item) async throws -> ([Change], [Item]) {
        var changes: [Change] = []
        var remainder: [Item] = []

        let dbItems = try await Dictionary(
            uniqueKeysWithValues: db.children(of: folder.id).map {
                ($0.name, $0)
            }
        )

        let sshItems = try await withEntries(of: folder.id) { entries in
            var sshItems: [String: SFTPAttributes] = [:]
            for try await (name, attrs) in entries {
                sshItems[name] = attrs
            }
            return sshItems
        }

        for (name, sshItem) in sshItems {
            let dbItem = dbItems[name]
            if dbItem == nil
                || dbItem?.size != sshItem.size
                || dbItem?.modifyTime != sshItem.modifyTime
            {
                let newItem = try await upsert(
                    parentId: folder.id,
                    name: name,
                    attrs: sshItem
                )

                changes.append(.update(item: newItem))
            }
            
            if let dbItem = dbItem, dbItem.isEnumerated {
                remainder.append(dbItem)
            }
        }

        for (name, dbItem) in dbItems {
            if sshItems[name] == nil {
                try await db.remove(dbItem.id)
                changes.append(.delete(itemId: dbItem.rawId))
            }
        }

        return (changes, remainder)
    }

    func reconcile() async throws -> [Change] {
        var allChanges: [Change] = []
        var folders: [Item] = try await [
            db.item(for: .rootContainer),
            db.item(for: .trashContainer),
        ]

        while !folders.isEmpty {
            let nextFolder = folders.removeFirst()
            let (changes, remainder) = try await reconcile(
                folder: nextFolder
            )
            allChanges.append(contentsOf: changes)
            folders.append(contentsOf: remainder)
        }

        return allChanges
    }

    func enumerate(itemId: NSFileProviderItemIdentifier) async throws {
        try await withEntries(of: itemId) { entries in
            for try await (name, attrs) in entries {
                try await upsert(parentId: itemId, name: name, attrs: attrs)
            }
        }
        try await db.markEnumerated(itemId)
    }

    func symlinkTarget(for name: String, parentId: NSFileProviderItemIdentifier)
        async throws -> String
    {
        try await mapError(with: parentId) {
            try await sftp.symlinkTarget(
                at: path(for: name, parentId: parentId)
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
        try await logger.info(
            "Set attributes of \(id(of: itemId)): \(changes.joined(separator: ", "))"
        )
        try await mapError(with: itemId) {
            try await sftp.setAttributes(
                at: path(for: itemId),
                permissions: permissions,
                accessTime: accessTime,
                modifyTime: modifyTime
            )
            try await db.setAttributes(
                for: itemId,
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
        parentId: NSFileProviderItemIdentifier,
        name: String,
        target: String
    ) async throws -> Item {
        let path = try await self.path(for: name, parentId: parentId)
        logger.info("Create symlink \(path) -> \(target)")
        try await mapError(with: parentId) {
            try await sftp.createSymlink(to: target, at: path)
        }
        return try await record(
            parentId: parentId,
            name: name,
            kind: .symlink(target: target)
        )
    }

    func createDirectory(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        mode: mode_t = 0o700,
        ifExists: OnExists = .fail
    ) async throws -> Item {
        let path = try await self.path(for: name, parentId: parentId)
        logger.info(
            "Create directory \(path) with permissions \(String(mode, radix: 8))"
        )
        do {
            try await sftp.createDirectory(at: path, mode: mode)
        } catch SSHError.sftpError(.fileAlreadyExists, _) {
            switch ifExists {
            case .succeed:
                logger.info("Directory already exists at \(path)")
            case .fail:
                throw AgentError.filenameCollision
            }
        }
        return try await record(
            parentId: parentId,
            name: name,
            kind: .folder
        )
    }

    private func refresh(id: NSFileProviderItemIdentifier) async throws {
        let attrs = try await mapError(with: id) {
            try await sftp.attributes(
                at: path(for: id),
                followSymlinks: false
            )
        }
        try await db.refresh(
            id,
            size: attrs.size,
            permissions: attrs.permissions,
            accessTime: attrs.accessTime,
            modifyTime: attrs.modifyTime,
            createTime: attrs.createTime
        )
    }

    private func record(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        kind: Item.Kind
    ) async throws -> Item {
        let path = try await self.path(for: name, parentId: parentId)
        let attrs = try await mapError(with: parentId) {
            try await sftp.attributes(at: path, followSymlinks: false)
        }
        try await refresh(id: parentId)
        return try await db.upsert(
            parentId: parentId,
            name: name,
            kind: ItemModel.Kind(from: kind),
            size: attrs.size,
            permissions: attrs.permissions,
            accessTime: attrs.accessTime,
            modifyTime: attrs.modifyTime,
            createTime: attrs.createTime
        )
    }

    func move(
        _ itemId: NSFileProviderItemIdentifier,
        toParent newParentId: NSFileProviderItemIdentifier,
        name newName: String
    ) async throws {
        let oldPath = try await path(for: itemId)
        let newPath = try await path(for: newName, parentId: newParentId)

        try await logger.info("Move \(id(of: itemId)) to \(newPath)")
        try await mapError(with: itemId) {
            do {
                try await sftp.move(from: oldPath, to: newPath)
            } catch SSHError.sftpError(.noSuchFile, _)
                where newParentId == .trashContainer
            {
                logger.info("Trash doesn't exist, creating")
                try await sftp.createDirectoryRecursively(
                    at: path(for: newParentId),
                    mode: 0o700
                )
                try await sftp.move(from: oldPath, to: newPath)
            }
            try await refresh(id: newParentId)
            try await db.move(itemId, toParent: newParentId, name: newName)
        }
    }

    func removeFile(
        for itemId: NSFileProviderItemIdentifier
    ) async throws {
        try await logger.info("Remove \(id(of: itemId))")
        try await mapError(with: itemId) {
            try await sftp.removeFile(at: path(for: itemId))
            try await refresh(id: db.parent(of: itemId).id)
            try await db.remove(itemId)
        }
    }

    func removeDirectory(
        for itemId: NSFileProviderItemIdentifier
    ) async throws {
        try await logger.info("Remove directory \(id(of: itemId))")
        try await mapError(with: itemId) {
            try await sftp.removeDirectoryRecursively(at: path(for: itemId))
            try await refresh(id: db.parent(of: itemId).id)
            try await db.remove(itemId)
        }
    }

    func upload(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        file url: URL,
        mode: mode_t,
        chunkSize: UInt64 = SFTPLimits.defaultBufferSize,
        progress: Progress,
    ) async throws -> Item {
        let path = try await self.path(for: name, parentId: parentId)
        let fp = try FileHandle(forReadingFrom: url)
        defer { try? fp.close() }

        logger.info("Upload \(path) from \(url.path())")
        let size = try FileManager.default.size(of: url)

        progress.kind = .file
        progress.fileOperationKind = .uploading
        let speedometer = Speedometer(
            progress: progress,
            totalUnitCount: Int64(size)
        )

        let bufferSize = sftp.limits.writeLength(for: chunkSize)
        try await mapError(with: parentId) {
            try await sftp.withSftpFile(
                at: path,
                accessType: .writeOnly,
                mode: mode
            ) { file in
                try await file.withAsyncWriter { writer in
                    while let data = try fp.read(upToCount: Int(bufferSize)) {
                        if progress.isCancelled {
                            logger.info("Upload \(path) cancelled")
                            throw AgentError.userCancelled
                        }
                        try await writer.write(data: data)
                        if let progress = speedometer.update(delta: data.count)
                        {
                            logger.debug("Uploading \(path): \(progress)")
                        }
                    }
                }
            }
        }

        logger.info("Uploaded \(path): \(speedometer.finalize())")
        return try await record(parentId: parentId, name: name, kind: .file)
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
    ) async throws -> (URL, Item) {
        let item = try await item(for: itemId)
        let url = sharedUrl.appending(path: itemId.rawValue)
        logger.info("Download \(item) into \(url)")

        try create(file: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        progress.kind = .file
        progress.fileOperationKind = .downloading
        let speedometer = Speedometer(
            progress: progress,
            totalUnitCount: Int64(item.size ?? 0)
        )

        let bufferSize = sftp.limits.readLength(for: chunkSize)
        try await withFile(for: itemId, accessType: .readOnly) { fp in
            for try await data in fp.stream(bufferSize: bufferSize) {
                if progress.isCancelled {
                    logger.info("Download \(item) cancelled")
                    throw AgentError.userCancelled
                }
                try handle.write(contentsOf: data)
                if let progress = speedometer.update(delta: data.count) {
                    logger.debug("Downloading \(item): \(progress)")
                }
            }
        }

        logger.info("Downloaded \(item): \(speedometer.finalize())")
        return (url, item)
    }

    func stream(
        itemId: NSFileProviderItemIdentifier,
        range: Range<UInt64>,
        progress: Progress
    ) async throws -> (URL, Range<UInt64>) {
        let file = try await File(item: item(for: itemId))
        let url = sharedUrl.appending(path: "\(itemId.rawValue)")
        let slice = file.slice(for: range)

        logger.info("Stream \(range) -> \(slice) into \(url)")
        try create(file: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        progress.kind = .file
        progress.fileOperationKind = .downloading
        let speedometer = Speedometer(
            progress: progress,
            totalUnitCount: Int64(slice.byteRange.length)
        )

        for chunk in slice {
            let data = try await cache.fetch(chunk)
            try handle.seek(toOffset: chunk.byteRange.lowerBound)
            try handle.write(contentsOf: data)
            speedometer.update(delta: data.count)
        }

        let prefetchRange =
            slice.chunks.upperBound..<slice.chunks.upperBound
            + FileCache.prefetchWindow
        if !prefetchRange.isEmpty {
            for chunkIndex in prefetchRange {
                await cache.prefetch(file.chunk(at: chunkIndex))
            }
        }

        logger.info("Streamed \(slice): \(speedometer.finalize())")
        return (url, slice.byteRange)
    }

    func withFile<T: Sendable>(
        for itemId: NSFileProviderItemIdentifier,
        accessType: AccessType,
        mode: mode_t = 0o600,
        perform: @Sendable (SFTPFile) async throws -> T
    ) async throws -> T {
        try await logger.info("With \(accessType) file \(id(of: itemId))")
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
        try await logger.info("With directory \(id(of: itemId))")
        return try await mapError(with: itemId) {
            try await sftp.withDirectory(
                at: path(for: itemId),
                perform: perform
            )
        }
    }

    typealias Entry = (name: String, attrs: SFTPAttributes)
    typealias EntryAsyncSequence = AsyncSequence<Entry, SSHError>
    
    struct EmptyEntryAsyncSequence: EntryAsyncSequence {
        struct AsyncIterator: AsyncIteratorProtocol {
            mutating func next() async throws(SSHError) -> Entry? { nil }
        }
        
        func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
    }

    func withEntries<T: Sendable>(
        of itemId: NSFileProviderItemIdentifier,
        perform: @Sendable (any EntryAsyncSequence) async throws -> T
    ) async throws -> T {
        do {
            return try await withDirectory(for: itemId) { dir in
                let entries = dir.compactMap { attrs -> Entry? in
                    guard let name = attrs.name else { return nil }
                    if itemId == .rootContainer, name == ".sshadow" {
                        return nil
                    }
                    return (name, attrs)
                }
                return try await perform(entries)
            }
        } catch AgentError.itemNotFound where itemId == .trashContainer {
            return try await perform(EmptyEntryAsyncSequence())
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
