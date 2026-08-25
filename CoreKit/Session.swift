import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "Session")

actor Session {
    typealias Provider =
        @Sendable (ConnectionConfig, @escaping ConnectionLostHandler)
        async throws(ConnectionError) -> Session
    typealias ChangesDetectedHandler = @Sendable () async throws -> Void
    typealias ConnectionLostHandler = @Sendable () async -> Void
    typealias IdleTimeProvider = @Sendable () -> Duration

    private let config: ConnectionConfig
    private let ssh: SSHClient
    private let sftp: SFTPClient
    private let db: DomainDB
    private let sharedUrl: URL
    private let changesDetectedHandler: ChangesDetectedHandler
    private let connectionLostHandler: ConnectionLostHandler
    private let idleTimeProvider: IdleTimeProvider
    private let transfers: Transfers

    private lazy var cache = FileCache(read: read)

    private var watched: [NSFileProviderItemIdentifier: Int] = [:]
    private var schedule: PollSchedule?
    private var pollTask: Task<Void, Never>?
    private(set) var reconcileTask: Task<[Change], any Error>?
    private(set) var outstanding = 0
    private var changes: [(UInt64, [Change])] = []
    private(set) var anchor: UInt64 = 0

    static func provider(
        domainDb: DomainDB,
        sharedUrl: URL,
        signalEnumerator: @escaping DomainRegistry.EnumeratorSignal,
        transfers: Transfers
    ) -> Provider {
        { config, handler in
            let (ssh, sftp) = try await SSHClient.connect(config: config)
            return Session(
                config: config,
                ssh: ssh,
                sftp: sftp,
                db: domainDb,
                sharedUrl: sharedUrl,
                changesDetectedHandler: { try await signalEnumerator(config) },
                connectionLostHandler: handler,
                idleTimeProvider: SystemIdle.duration,
                transfers: transfers
            )
        }
    }

    init(
        config: ConnectionConfig,
        ssh: SSHClient,
        sftp: SFTPClient,
        db: DomainDB,
        sharedUrl: URL = SSHadow.groupUrl,
        changesDetectedHandler: @escaping ChangesDetectedHandler,
        connectionLostHandler: @escaping ConnectionLostHandler,
        idleTimeProvider: @escaping IdleTimeProvider,
        transfers: Transfers,
    ) {
        self.config = config
        self.ssh = ssh
        self.sftp = sftp
        self.db = db
        self.sharedUrl = sharedUrl
        self.changesDetectedHandler = changesDetectedHandler
        self.connectionLostHandler = connectionLostHandler
        self.idleTimeProvider = idleTimeProvider
        self.transfers = transfers

        let dbConfig = db.modelContainer.configurations.first
        let dbPath = dbConfig?.url.path ?? "in-memory"
        logger.info("SSH connected: \(config), DB: \(dbPath)")
    }

    var limits: Limits {
        Limits(
            maxReadLength: sftp.limits.maxReadLength,
            maxWriteLength: sftp.limits.maxWriteLength
        )
    }

    func close() async {
        await sftp.close()
        await ssh.close()

        logger.info("SSH disconnected: \(config)")
    }

    func start(pollInterval: Duration?) {
        guard pollTask == nil, let pollInterval else { return }
        schedule = PollSchedule(
            begin: ContinuousClock.now,
            allInterval: pollInterval
        )
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                do {
                    try await tick()
                } catch CoreError.serverUnreachable {
                    break
                } catch is CancellationError {
                    logger.debug("Poll interrupted by operation")
                } catch {
                    logger.error("Poll error: \(error)")
                }
            }
            logger.info("Poll cancelled: \(config)")
        }
    }

    func tick() async throws {
        guard let schedule else { return }
        guard outstanding == 0 else { return }
        switch schedule.next(
            now: ContinuousClock.now,
            userIdle: idleTimeProvider()
        ) {
        case .pollAll:
            try await pollAll()
            schedule.recordPollAll(at: ContinuousClock.now)
        case .pollWatched:
            try await pollWatched()
            schedule.recordPollWatched(at: ContinuousClock.now)
        case .wait:
            break
        }
    }

    func stop() {
        reconcileTask?.cancel()
        pollTask?.cancel()
        pollTask = nil
    }

    func pollAll() async throws {
        logger.debug(
            "Poll all: \(config.url), anchor: \(anchor)"
        )

        let reconcileTask = Task { try await reconcileAll() }
        self.reconcileTask = reconcileTask
        defer { self.reconcileTask = nil }
        let newChanges = try await reconcileTask.value
        guard !newChanges.isEmpty else {
            return
        }

        changes.append((anchor, newChanges))
        anchor += 1

        logger.info(
            "Polled all: \(newChanges.count) change(s), anchor: \(anchor)"
        )
        try await changesDetectedHandler()
    }

    func reconcileAll() async throws -> [Change] {
        var allChanges: [Change] = []
        var folders: [Item] = try await [
            db.item(for: .rootContainer),
            db.item(for: .trashContainer),
        ]

        while !folders.isEmpty {
            try Task.checkCancellation()
            let nextFolder = folders.removeFirst()
            let (changes, remainder) = try await reconcile(
                folder: nextFolder
            )
            allChanges.append(contentsOf: changes)
            folders.append(contentsOf: remainder)
        }

        return allChanges
    }

    func watch(itemId: NSFileProviderItemIdentifier) {
        guard itemId != .workingSet, itemId != .trashContainer else { return }
        watched[itemId, default: 0] += 1
        schedule?.recordWatchStarted()
        if watched[itemId] == 1 {
            logger.info("Started watching: \(itemId)")
        }
    }

    func unwatch(itemId: NSFileProviderItemIdentifier) {
        guard itemId != .workingSet, itemId != .trashContainer else { return }
        guard let count = watched[itemId] else { return }
        if count <= 1 {
            watched.removeValue(forKey: itemId)
            logger.info("Stopped watching: \(itemId)")
        } else {
            watched[itemId] = count - 1
        }
    }

    func pollWatched() async throws {
        guard !watched.isEmpty else { return }

        logger.debug(
            "Poll watched: \(config.url), anchor: \(anchor), items: \(watched.keys)"
        )

        let reconcileTask = Task { try await reconcileWatched() }
        self.reconcileTask = reconcileTask
        defer { self.reconcileTask = nil }
        let newChanges = try await reconcileTask.value
        guard !newChanges.isEmpty else {
            return
        }

        changes.append((anchor, newChanges))
        anchor += 1

        logger.info(
            "Polled watched: \(newChanges.count) change(s), anchor: \(anchor), items: \(watched.keys)"
        )
        try await changesDetectedHandler()
    }

    func reconcileWatched() async throws -> [Change] {
        var allChanges: [Change] = []

        for itemId in Array(watched.keys) {
            try Task.checkCancellation()
            do {
                let item = try await db.item(for: itemId)
                let changes: [Change]
                if item.kind == .folder {
                    (changes, _) = try await reconcile(folder: item)
                } else {
                    changes = try await reconcile(file: item)
                }
                allChanges.append(contentsOf: changes)
            } catch CoreError.serverUnreachable {
                throw CoreError.serverUnreachable
            } catch CoreError.itemNotFound {
                watched.removeValue(forKey: itemId)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.error("Reconcile watched \(itemId) failed: \(error)")
            }
        }

        return allChanges
    }

    private func reconcile(folder: Item) async throws -> ([Change], [Item]) {
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
            changes.append(
                contentsOf: try await reconcile(
                    dbItem,
                    against: sshItem,
                    parentId: folder.id
                )
            )

            if let dbItem,
                dbItem.kind == sshItem.kind,
                dbItem.kind == .folder,
                dbItem.enumeratedAt != nil
            {
                remainder.append(dbItem)
            }
        }

        for (name, dbItem) in dbItems where sshItems[name] == nil {
            logger.info("Reconcile deleted: \(dbItem)")
            try await db.remove(dbItem.id)
            await cache.invalidate(dbItem.id)
            changes.append(.delete(itemId: dbItem.rawId))
        }

        return (changes, remainder)
    }

    private func reconcile(file dbItem: Item) async throws -> [Change] {
        let attrs: SFTPAttributes
        do {
            attrs = try await attributes(for: dbItem.id)
        } catch CoreError.itemNotFound {
            logger.info("Reconcile deleted: \(dbItem)")
            try await db.remove(dbItem.id)
            await cache.invalidate(dbItem.id)
            watched.removeValue(forKey: dbItem.id)
            return [.delete(itemId: dbItem.rawId)]
        }

        guard let parentId = dbItem.parentId else { return [] }
        let sshItem = try await sshItem(
            for: dbItem.name,
            in: parentId,
            from: attrs
        )
        return try await reconcile(dbItem, against: sshItem, parentId: parentId)
    }

    private func reconcile(
        _ dbItem: Item?,
        against sshItem: SSHItem,
        parentId: NSFileProviderItemIdentifier
    ) async throws -> [Change] {
        var changes: [Change] = []

        if let dbItem, dbItem.kind != sshItem.kind {
            logger.info("Reconcile replaced: \(dbItem) -> \(sshItem)")
            try await db.remove(dbItem.id)
            await cache.invalidate(dbItem.id)
            changes.append(.delete(itemId: dbItem.rawId))
        }

        let newItem = try await upsert(parentId: parentId, sshItem: sshItem)

        guard let dbItem, dbItem.kind == sshItem.kind else {
            logger.info("Reconcile new: \(sshItem)")
            changes.append(.update(item: newItem))
            return changes
        }

        if changed(dbItem, versus: sshItem) {
            logger.info("Reconcile changed: \(dbItem) -> \(sshItem)")
            if dbItem.kind == .file {
                await cache.invalidate(dbItem.id)
            }
            changes.append(.update(item: newItem))
        }

        return changes
    }

    private func changed(_ dbItem: Item, versus sshItem: SSHItem) -> Bool {
        switch dbItem.kind {
        case .file:
            dbItem.size != sshItem.size
                || dbItem.flags != sshItem.flags
                || dbItem.createTime != sshItem.createTime
                || dbItem.modifyTime != sshItem.modifyTime
        case .folder:
            dbItem.flags != sshItem.flags
                || dbItem.createTime != sshItem.createTime
                || dbItem.modifyTime != sshItem.modifyTime
        case .symlink:
            dbItem.createTime != sshItem.createTime
                || dbItem.modifyTime != sshItem.modifyTime
        }
    }

    func changes(since prevAnchor: UInt64) -> (UInt64, [Change]) {
        let allChanges =
            changes
            .filter { anchor, _ in anchor >= prevAnchor }
            .flatMap { _, rowChanges in rowChanges }
        return (anchor, allChanges)
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
        in parentId: NSFileProviderItemIdentifier
    ) async throws -> String {
        try await config.path(for: db.path(for: name, in: parentId))
    }

    func item(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> Item {
        try await db.item(for: itemId)
    }

    func list(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> [Item] {
        outstanding += 1
        reconcileTask?.cancel()
        defer { outstanding -= 1 }

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
        try await db.upsert(
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

    func enumerate(itemId: NSFileProviderItemIdentifier) async throws {
        try await withEntries(of: itemId) { entries in
            for try await sshItem in entries {
                try await upsert(parentId: itemId, sshItem: sshItem)
            }
        }
        try await db.markEnumerated(itemId)
    }

    @discardableResult
    func setAttributes(
        for itemId: NSFileProviderItemIdentifier,
        flags: Item.Flags? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil
    ) async throws -> Item {
        outstanding += 1
        reconcileTask?.cancel()
        defer { outstanding -= 1 }

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
                permissions: flags?.mode(umask: 0o022),
                accessTime: accessTime,
                modifyTime: modifyTime
            )
        }
        try await db.setAttributes(
            for: itemId,
            flags: flags,
            accessTime: accessTime,
            modifyTime: modifyTime
        )
        return try await item(for: itemId)
    }

    func createSymlink(
        _ name: String,
        in parentId: NSFileProviderItemIdentifier,
        target: String
    ) async throws -> Item {
        outstanding += 1
        reconcileTask?.cancel()
        defer { outstanding -= 1 }

        let path = try await path(for: name, in: parentId)
        logger.info("Create symlink \(path) -> \(target)")
        try await mapError(with: parentId) {
            try await sftp.createSymlink(to: target, at: path)
        }
        return try await record(
            name,
            in: parentId,
            kind: .symlink(target: target)
        )
    }

    func createDirectory(
        _ name: String,
        in parentId: NSFileProviderItemIdentifier,
        flags: Item.Flags = .all,
        ifExists: OnExists = .fail
    ) async throws -> Item {
        outstanding += 1
        reconcileTask?.cancel()
        defer { outstanding -= 1 }

        let path = try await path(for: name, in: parentId)
        logger.info("Create directory \(path)")
        try await mapError(with: parentId) {
            do {
                try await sftp.createDirectory(at: path, mode: flags.mode)
            } catch SSHError.sftpError(.fileAlreadyExists, _) {
                switch ifExists {
                case .succeed:
                    logger.info("Directory already exists at \(path)")
                case .fail:
                    throw CoreError.filenameCollision
                }
            }
        }
        return try await record(name, in: parentId, kind: .folder)
    }

    @discardableResult
    func move(
        _ itemId: NSFileProviderItemIdentifier,
        to newParentId: NSFileProviderItemIdentifier,
        name newName: String
    ) async throws -> Item {
        outstanding += 1
        reconcileTask?.cancel()
        defer { outstanding -= 1 }

        let oldPath = try await path(for: itemId)
        let newPath = try await path(for: newName, in: newParentId)

        try await logger.info("Move \(id(of: itemId)) to \(newPath)")
        try await mapError(with: itemId) {
            do {
                try await sftp.move(from: oldPath, to: newPath)
            } catch SSHError.sftpError(.noSuchFile, _)
                where newParentId == .trashContainer
            {
                logger.info("Trash doesn't exist, creating")
                try await sftp.createDirectoryRecursively(
                    at: path(for: newParentId)
                )
                try await sftp.move(from: oldPath, to: newPath)
            }
        }
        try await refresh(newParentId)
        try await db.move(itemId, toParent: newParentId, name: newName)
        return try await item(for: itemId)
    }

    func removeFile(
        for itemId: NSFileProviderItemIdentifier
    ) async throws {
        outstanding += 1
        reconcileTask?.cancel()
        defer { outstanding -= 1 }

        try await logger.info("Remove \(id(of: itemId))")
        try await mapError(with: itemId) {
            try await sftp.removeFile(at: path(for: itemId))
        }
        try await refresh(db.parent(of: itemId).id)
        try await db.remove(itemId)
    }

    func removeDirectory(
        for itemId: NSFileProviderItemIdentifier
    ) async throws {
        outstanding += 1
        reconcileTask?.cancel()
        defer { outstanding -= 1 }

        try await logger.info("Remove directory \(id(of: itemId))")
        try await mapError(with: itemId) {
            try await sftp.removeDirectoryRecursively(at: path(for: itemId))
        }
        try await refresh(db.parent(of: itemId).id)
        try await db.remove(itemId)
    }

    func upload(
        _ name: String,
        to parentId: NSFileProviderItemIdentifier,
        file url: URL,
        flags: Item.Flags,
        chunkSize: UInt64 = SFTPLimits.defaultBufferSize,
        progress: Progress
    ) async throws -> Item {
        outstanding += 1
        reconcileTask?.cancel()
        defer { outstanding -= 1 }

        let path = try await path(for: name, in: parentId)
        let fp = try FileHandle(forReadingFrom: url)
        defer { try? fp.close() }

        logger.info("Upload \(path) from \(url.path)")
        let size = try FileManager.default.size(of: url)

        progress.kind = .file
        progress.fileOperationKind = .uploading

        let transfer = await transfers.begin(
            name: name,
            progress: progress
        )
        defer { transfers.end(transfer: transfer) }

        let estimator = ThroughputEstimator(
            progress: progress,
            totalUnitCount: Int64(size),
            reporters: [
                transferProgressReporter(for: transfer),
                loggingProgressReporter(for: "Upload", detail: path),
            ]
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
                            throw CoreError.userCancelled
                        }
                        try await writer.write(data: data)
                        estimator.update(delta: data.count)
                    }
                }
            }
        }

        estimator.finalize()
        return try await record(name, in: parentId, kind: .file)
    }

    func download(
        itemId: NSFileProviderItemIdentifier,
        chunkSize: UInt64 = SFTPLimits.defaultBufferSize,
        progress: Progress
    ) async throws -> (URL, Item) {
        outstanding += 1
        reconcileTask?.cancel()
        defer { outstanding -= 1 }

        let item = try await item(for: itemId)
        let url = sharedUrl.appending(path: itemId.rawValue)
        logger.info("Download \(item) into \(url)")

        try create(file: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        progress.kind = .file
        progress.fileOperationKind = .downloading

        let transfer = await transfers.begin(
            name: item.name,
            progress: progress
        )
        defer { transfers.end(transfer: transfer) }

        let estimator = ThroughputEstimator(
            progress: progress,
            totalUnitCount: Int64(item.size ?? 0),
            reporters: [
                transferProgressReporter(for: transfer),
                loggingProgressReporter(for: "Download", detail: item),
            ]
        )

        let bufferSize = sftp.limits.readLength(for: chunkSize)
        try await withFile(for: itemId, accessType: .readOnly) { fp in
            for try await data in fp.stream(bufferSize: bufferSize) {
                if progress.isCancelled {
                    logger.info("Download \(item) cancelled")
                    throw CoreError.userCancelled
                }
                try handle.write(contentsOf: data)
                estimator.update(delta: data.count)
            }
        }

        estimator.finalize()
        return (url, item)
    }

    func stream(
        itemId: NSFileProviderItemIdentifier,
        range: Range<UInt64>,
        progress: Progress
    ) async throws -> (URL, Range<UInt64>) {
        outstanding += 1
        reconcileTask?.cancel()
        defer { outstanding -= 1 }

        let item = try await item(for: itemId)
        let file = File(item: item)
        let url = sharedUrl.appending(path: "\(itemId.rawValue)")
        let slice = file.slice(for: range)

        logger.info("Stream \(range) -> \(slice) into \(url)")
        try create(file: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        progress.kind = .file
        progress.fileOperationKind = .downloading

        let estimator = ThroughputEstimator(
            progress: progress,
            totalUnitCount: Int64(slice.byteRange.length),
            reporters: [
                loggingProgressReporter(for: "Stream", detail: slice)
            ]
        )

        for chunk in slice {
            let data = try await cache.fetch(chunk)
            try handle.seek(toOffset: chunk.byteRange.lowerBound)
            try handle.write(contentsOf: data)
            estimator.update(delta: data.count)
        }

        let prefetchRange =
            slice.chunks.upperBound..<slice.chunks.upperBound
            + FileCache.prefetchWindow
        if !prefetchRange.isEmpty {
            for chunkIndex in prefetchRange {
                await cache.prefetch(file.chunk(at: chunkIndex))
            }
        }

        estimator.finalize()
        return (url, slice.byteRange)
    }

    private func record(
        _ name: String,
        in parentId: NSFileProviderItemIdentifier,
        kind: Item.Kind
    ) async throws -> Item {
        let attrs = try await attributes(for: name, in: parentId)
        try await refresh(parentId)
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

    private func refresh(_ itemId: NSFileProviderItemIdentifier) async throws {
        let attrs = try await attributes(for: itemId)
        try await db.refresh(
            itemId,
            size: attrs.size,
            flags: .from(attrs.permissions),
            accessTime: attrs.accessTime,
            modifyTime: attrs.modifyTime,
            createTime: attrs.createTime
        )
    }
    
    private func attributes(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> SFTPAttributes {
        try await mapError(with: itemId) {
            try await sftp.attributes(
                at: path(for: itemId),
                followSymlinks: false
            )
        }
    }

    private func attributes(
        for name: String,
        in parentId: NSFileProviderItemIdentifier
    ) async throws -> SFTPAttributes {
        try await mapError(with: parentId) {
            try await sftp.attributes(
                at: path(for: name, in: parentId),
                followSymlinks: false
            )
        }
    }

    private func create(file url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path()) {
            try Data().write(to: url)
        }
    }

    private func read(
        _ itemId: NSFileProviderItemIdentifier,
        range: Range<UInt64>
    ) async throws -> Data {
        try await withFile(
            for: itemId,
            accessType: .readOnly
        ) { file in
            try await file.read(range: range)
        }
    }

    private func withFile<T: Sendable>(
        for itemId: NSFileProviderItemIdentifier,
        accessType: AccessType,
        mode: mode_t = 0o666,
        perform: @Sendable (SFTPFile) async throws -> T
    ) async throws -> T {
        try await mapError(with: itemId) {
            try await sftp.withSftpFile(
                at: path(for: itemId),
                accessType: accessType,
                mode: mode,
                perform: perform
            )
        }
    }

    private func withDirectory<T: Sendable>(
        for itemId: NSFileProviderItemIdentifier,
        perform: @Sendable (SFTPDirectory) async throws -> T
    ) async throws -> T {
        try await mapError(with: itemId) {
            try await sftp.withDirectory(
                at: path(for: itemId),
                perform: perform
            )
        }
    }

    private func withEntries<T: Sendable>(
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
                    return try await self.sshItem(
                        for: name,
                        in: itemId,
                        from: attrs
                    )
                }
                return try await perform(entries)
            }
        } catch CoreError.itemNotFound where itemId == .trashContainer {
            return try await perform(SSHItem.EmptyStream())
        }
    }

    private func sshItem(
        for name: String,
        in parentId: NSFileProviderItemIdentifier,
        from attrs: SFTPAttributes
    ) async throws -> SSHItem {
        let kind: Item.Kind =
            switch attrs.type {
            case .directory:
                .folder
            case .symlink:
                .symlink(
                    target: try await symlinkTarget(
                        for: name,
                        in: parentId
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

    private func symlinkTarget(
        for name: String,
        in parentId: NSFileProviderItemIdentifier
    ) async throws -> String {
        try await mapError(with: parentId) {
            try await sftp.symlinkTarget(
                at: path(for: name, in: parentId)
            )
        }
    }

    private func mapError<T>(
        with itemId: NSFileProviderItemIdentifier,
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as SSHError
            where error.isConnectionFailed || error.sftpError == .failure
            || error.sftpError == .connectionLost
            || error.sftpError == .noConnection
        {
            logger.error("SSH connection lost: \(error)")
            await connectionLostHandler()
            throw CoreError.serverUnreachable
        } catch SSHError.sftpError(.noSuchFile, _) {
            throw CoreError.itemNotFound(itemId.rawValue)
        } catch SSHError.sftpError(.permissionDenied, _) {
            throw CoreError.permissionDenied
        } catch SSHError.sftpError(.fileAlreadyExists, _) {
            throw CoreError.filenameCollision
        }
    }

    private func transferProgressReporter(
        for transfer: Transfer
    ) -> ThrottledProgressReporter {
        ThrottledProgressReporter(
            frequency: TimeInterval(0.2),
            onUpdate: { _ in transfer.update() }
        )
    }

    private func loggingProgressReporter(
        for operation: String,
        detail: any CustomStringConvertible
    ) -> ThrottledProgressReporter {
        ThrottledProgressReporter(
            frequency: TimeInterval(1.0),
            onUpdate: {
                let desc = $0.localizedAdditionalDescription!
                logger.debug("\(operation)ing \(detail): \(desc)")
            },
            onFinalize: {
                let desc = $0.localizedAdditionalDescription!
                logger.info("\(operation)ed \(detail): \(desc)")
            }
        )
    }
}
