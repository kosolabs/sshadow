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
        try await db.child(of: parentId, name: name)
    }

    func parent(
        of itemId: NSFileProviderItemIdentifier
    ) async throws -> NSFileProviderItemIdentifier {
        try await db.parent(of: itemId)
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
        guard let model = await db.fetch(id: itemId) else {
            throw AgentError.itemNotFound(itemId.rawValue)
        }
        return Item(from: model)
    }

    func list(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> [Item] {
        if await !db.isEnumerated(itemId) {
            try await enumerate(itemId: itemId)
        }
        let models = await db.children(of: itemId)
        return models.map { model in Item(from: model) }
    }

    func reconcile(
        directory: NSFileProviderItemIdentifier
    ) async throws -> ([Change], [NSFileProviderItemIdentifier]) {
        var changes: [Change] = []
        var remainder: [NSFileProviderItemIdentifier] = []

        let currModels = await Dictionary(
            uniqueKeysWithValues: db.children(of: directory).map {
                ($0.name, $0)
            }
        )

        let currAttrs = try await withDirectory(for: directory) { dir in
            var currAttrs: [String: SFTPAttributes] = [:]
            for try await attrs in dir {
                guard let name = attrs.name else { continue }
                currAttrs[name] = attrs
            }
            return currAttrs
        }

        for (name, attrs) in currAttrs {
            if let model = currModels[name] {
                if model.size != attrs.size
                    || model.modifyTime != attrs.modifyTime
                {
                    let newItem = try await db.upsert(
                        parentId: model.parentId,
                        name: name,
                        kind: model.kind,
                        size: attrs.size,
                        permissions: attrs.permissions,
                        accessTime: attrs.accessTime,
                        modifyTime: attrs.modifyTime,
                        createTime: attrs.createTime
                    )

                    changes.append(.update(item: Item(from: newItem)))
                }
            }
        }

        for (name, model) in currModels {
            if currAttrs[name] == nil {
                // TODO: Actually remove the item from the DB

                changes.append(.delete(itemId: model.rawId))
            }
        }

        return (changes, remainder)
    }

    func reconcile() async throws -> [Change] {
        var allChanges: [Change] = []
        var folders: [NSFileProviderItemIdentifier] = [.rootContainer]

        while !folders.isEmpty {
            let nextFolder = folders.removeFirst()
            let (changes, remainder) = try await reconcile(
                directory: nextFolder
            )
            allChanges.append(contentsOf: changes)
            folders.append(contentsOf: remainder)
        }

        return allChanges
    }

    func enumerate(itemId: NSFileProviderItemIdentifier) async throws {
        do {
            try await withDirectory(for: itemId) { dir in
                for try await attrs in dir {
                    guard let name = attrs.name else { continue }

                    let kind: ItemModel.Kind =
                        switch attrs.type {
                        case .directory:
                            .folder
                        case .symlink:
                            .symlink(
                                target: try await symlinkTarget(
                                    for: name,
                                    parentId: itemId
                                )
                            )
                        default:
                            .file
                        }

                    try await db.upsert(
                        parentId: itemId,
                        name: name,
                        kind: kind,
                        size: attrs.size,
                        permissions: attrs.permissions,
                        accessTime: attrs.accessTime,
                        modifyTime: attrs.modifyTime,
                        createTime: attrs.createTime
                    )
                }
            }
        } catch AgentError.itemNotFound where itemId == .trashContainer {
            try await db.markEnumerated(itemId)
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

    private func refresh(
        id: NSFileProviderItemIdentifier,
    ) async throws {
        guard var model = await db.fetch(id: id) else { return }
        let attrs = try await mapError(with: id) {
            try await sftp.attributes(at: path(for: id), followSymlinks: false)
        }
        model.size = attrs.size
        model.permissions = attrs.permissions
        model.accessTime = attrs.accessTime
        model.modifyTime = attrs.modifyTime
        model.createTime = attrs.createTime
        try await db.upsert(model)
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
        let model = try await db.upsert(
            parentId: parentId,
            name: name,
            kind: ItemModel.Kind(from: kind),
            size: attrs.size,
            permissions: attrs.permissions,
            accessTime: attrs.accessTime,
            modifyTime: attrs.modifyTime,
            createTime: attrs.createTime
        )
        return Item(from: model)
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
            try await refresh(id: db.parent(of: itemId))
            try await db.remove(itemId)
        }
    }

    func removeDirectory(
        for itemId: NSFileProviderItemIdentifier
    ) async throws {
        try await logger.info("Remove directory \(id(of: itemId))")
        try await mapError(with: itemId) {
            try await sftp.removeDirectoryRecursively(at: path(for: itemId))
            try await refresh(id: db.parent(of: itemId))
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
