import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "Session")

public typealias SignalEnumerator = @Sendable (ConnectionConfig) async throws -> Void

public let defaultSignalEnumerator: SignalEnumerator = { config in
    try await config.domain.manager.signalEnumerator(for: .workingSet)
}

actor Session {
    private let config: ConnectionConfig
    private let ssh: SSHClient
    private let sftp: SFTPClient
    private let db: DomainDB
    private let sharedUrl: URL
    private let signal: SignalEnumerator

    private let cache: FileCache
    private var changes: [(UInt64, [Change])] = []
    private var anchor: UInt64 = 0

    init(
        config: ConnectionConfig,
        ssh: SSHClient,
        sftp: SFTPClient,
        db: DomainDB,
        sharedUrl: URL = SSHadow.groupUrl,
        signal: @escaping SignalEnumerator
    ) {
        self.config = config
        self.ssh = ssh
        self.sftp = sftp
        self.db = db
        self.sharedUrl = sharedUrl
        self.signal = signal

        self.cache = FileCache { itemId, range in
            let path = try await config.path(for: db.path(for: itemId))
            return try await sftp.withSftpFile(
                at: path,
                accessType: .readOnly
            ) { file in
                try await file.read(range: range)
            }
        }

        if let dbConfig = db.modelContainer.configurations.first {
            logger.info("Connected: \(config.url), DB: \(dbConfig.url.path)")
        } else {
            logger.info("Connected: \(config.url)")
        }
    }

    func close() async {
        await sftp.close()
        await ssh.close()

        logger.info("Disconnected: \(config.url)")
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
        sshItem: SSHItem
    ) async throws -> Item {
        return try await db.upsert(
            parentId: parentId,
            name: sshItem.name,
            kind: sshItem.kind,
            size: sshItem.size,
            flags: sshItem.flags,
            accessTime: sshItem.accessTime,
            modifyTime: sshItem.modifyTime,
            createTime: sshItem.createTime
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
            var sshItems: [String: SSHItem] = [:]
            for try await sshItem in entries {
                sshItems[sshItem.name] = sshItem
            }
            return sshItems
        }

        for (name, sshItem) in sshItems {
            let dbItem = dbItems[name]

            if let dbItem, dbItem.kind != sshItem.kind {
                logger.info("Reconcile replaced: \(dbItem) -> \(sshItem)")
                try await db.remove(dbItem.id)
                changes.append(.delete(itemId: dbItem.rawId))
            }

            let newItem = try await upsert(
                parentId: folder.id,
                sshItem: sshItem
            )

            guard let dbItem, dbItem.kind == sshItem.kind else {
                logger.info("Reconcile new: \(sshItem)")
                changes.append(.update(item: newItem))
                continue
            }

            switch dbItem.kind {
            case .file:
                if dbItem.size != sshItem.size
                    || dbItem.flags != sshItem.flags
                    || dbItem.createTime != sshItem.createTime
                    || dbItem.modifyTime != sshItem.modifyTime
                {
                    logger.info("Reconcile file: \(dbItem) -> \(sshItem)")
                    changes.append(.update(item: newItem))
                }
            case .folder:
                if dbItem.flags != sshItem.flags
                    || dbItem.createTime != sshItem.createTime
                    || dbItem.modifyTime != sshItem.modifyTime
                {
                    logger.info("Reconcile folder: \(dbItem) -> \(sshItem)")
                    changes.append(.update(item: newItem))
                }

                if dbItem.enumeratedAt != nil {
                    remainder.append(dbItem)
                }
            case .symlink:
                if dbItem.createTime != sshItem.createTime
                    || dbItem.modifyTime != sshItem.modifyTime
                {
                    logger.info("Reconcile symlink: \(dbItem) -> \(sshItem)")
                    changes.append(.update(item: newItem))
                }
            }
        }

        for (name, dbItem) in dbItems {
            if sshItems[name] == nil {
                logger.info("Reconcile deleted: \(dbItem)")
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

    func poll() async throws {
        let newChanges = try await reconcile()
        guard !newChanges.isEmpty else {
            return
        }

        changes.append((anchor, newChanges))
        anchor += 1

        logger.info(
            "Poll anchor at \(anchor) with \(newChanges.count) change(s)"
        )
        try await signal(config)
    }

    var currentAnchor: UInt64 {
        anchor
    }

    func changes(since prevAnchor: UInt64) -> (UInt64, [Change]) {
        var allChanges: [Change] = []
        for (rowAnchor, rowChanges) in changes {
            if rowAnchor >= prevAnchor {
                allChanges.append(contentsOf: rowChanges)
            }
        }
        return (anchor, allChanges)
    }

    func enumerate(itemId: NSFileProviderItemIdentifier) async throws {
        try await withEntries(of: itemId) { entries in
            for try await sshItem in entries {
                try await upsert(parentId: itemId, sshItem: sshItem)
            }
        }
        try await db.markEnumerated(itemId)
    }

    func symlinkTarget(
        for name: String,
        parentId: NSFileProviderItemIdentifier
    ) async throws -> String {
        try await mapError(with: parentId) {
            try await sftp.symlinkTarget(
                at: path(for: name, parentId: parentId)
            )
        }
    }

    func setAttributes(
        for itemId: NSFileProviderItemIdentifier,
        flags: Item.Flags? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil
    ) async throws {
        var changes: [String] = []
        if let accessTime { changes.append("accessTime: \(accessTime)") }
        if let modifyTime { changes.append("modifyTime: \(modifyTime)") }
        if let flags { changes.append("permissions: \(flags)") }
        try await logger.info(
            "Set attributes of \(id(of: itemId)): \(changes.joined(separator: ", "))"
        )
        try await mapError(with: itemId) {
            try await sftp.setAttributes(
                at: path(for: itemId),
                permissions: flags?.mode,
                accessTime: accessTime,
                modifyTime: modifyTime
            )
            try await db.setAttributes(
                for: itemId,
                flags: flags,
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
            flags: .from(attrs.permissions),
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
            kind: kind,
            size: attrs.size,
            flags: .from(attrs.permissions),
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
        flags: Item.Flags,
        chunkSize: UInt64 = SFTPLimits.defaultBufferSize,
        progress: Progress,
    ) async throws -> Item {
        let path = try await self.path(for: name, parentId: parentId)
        let fp = try FileHandle(forReadingFrom: url)
        defer { try? fp.close() }

        logger.info("Upload \(path) from \(url.path)")
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
                mode: flags.mode
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
        try await logger.debug("With \(accessType) file \(id(of: itemId))")
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
        try await logger.debug("With directory \(id(of: itemId))")
        return try await mapError(with: itemId) {
            try await sftp.withDirectory(
                at: path(for: itemId),
                perform: perform
            )
        }
    }

    func withEntries<T: Sendable>(
        of itemId: NSFileProviderItemIdentifier,
        perform: @Sendable (any SSHItem.Stream) async throws -> T
    ) async throws -> T {
        do {
            return try await withDirectory(for: itemId) { dir in
                let entries = dir.compactMap { attrs -> SSHItem? in
                    guard let name = attrs.name else { return nil }
                    if itemId == .rootContainer, name == ".sshadow" {
                        return nil
                    }

                    let kind: Item.Kind =
                        switch attrs.type {
                        case .directory:
                            .folder
                        case .symlink:
                            .symlink(
                                target: try await self.symlinkTarget(
                                    for: name,
                                    parentId: itemId
                                )
                            )
                        default:
                            .file
                        }

                    return SSHItem(
                        name: name,
                        kind: kind,
                        size: attrs.size,
                        flags: .from(attrs.permissions),
                        accessTime: attrs.accessTime,
                        modifyTime: attrs.modifyTime,
                        createTime: attrs.createTime
                    )
                }
                return try await perform(entries)
            }
        } catch AgentError.itemNotFound where itemId == .trashContainer {
            return try await perform(SSHItem.EmptyStream())
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
