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
    private let transfers: Transfers<ContinuousClock>
    private let events: Events<ContinuousClock>

    nonisolated private let log: Events<ContinuousClock>.Logger
    nonisolated private let fileLog: Events<ContinuousClock>.Logger

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
        transfers: Transfers<ContinuousClock>,
        events: Events<ContinuousClock>
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
                transfers: transfers,
                events: events
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
        transfers: Transfers<ContinuousClock>,
        events: Events<ContinuousClock>
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
        self.events = events

        log = events.logger(for: .sync, connectionId: config.id)
        fileLog = events.logger(for: .file, connectionId: config.id)
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
                    log.warning("Sync failed", error: error)
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
        logger.debug("Poll: \(config.url), anchor: \(anchor)")

        let reconcileTask = Task { try await reconcileAll() }
        self.reconcileTask = reconcileTask
        defer { self.reconcileTask = nil }
        let newChanges = try await reconcileTask.value
        guard !newChanges.isEmpty else {
            return
        }

        record(newChanges)

        logger.info("Polled: \(newChanges.count) change(s), anchor: \(anchor)")
        log.notice("Detected \(newChanges.count) change(s) on server")
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
            "Poll: \(config.url), anchor: \(anchor), items: \(watched.keys)"
        )

        let reconcileTask = Task { try await reconcileWatched() }
        self.reconcileTask = reconcileTask
        defer { self.reconcileTask = nil }
        let newChanges = try await reconcileTask.value
        guard !newChanges.isEmpty else {
            return
        }

        record(newChanges)

        logger.info(
            "Polled: \(newChanges.count) change(s), anchor: \(anchor), items: \(watched.keys)"
        )
        log.notice("Detected \(newChanges.count) change(s) on server")
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

    private func record(_ newChanges: [Change]) {
        let now = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        anchor = max(now, anchor + 1)
        changes.append((anchor, newChanges))
    }

    func changes(since prevAnchor: UInt64) -> (UInt64, [Change]) {
        let result =
            changes
            .filter { anchor, _ in anchor > prevAnchor }
            .flatMap { _, rowChanges in rowChanges }

        changes.removeAll { anchor, _ in anchor <= prevAnchor }

        return (anchor, result)
    }

    func ref(for itemId: NSFileProviderItemIdentifier) async throws -> Ref {
        try await Ref(
            path: db.path(for: itemId),
            anchor: .item(id: itemId.rawValue)
        )
    }

    func ref(
        for name: String,
        in parentId: NSFileProviderItemIdentifier
    ) async throws -> Ref {
        try await Ref(
            path: db.path(for: name, in: parentId),
            anchor: .parent(id: parentId.rawValue)
        )
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

        let changes = {
            var changes: [String] = []
            if let accessTime { changes.append("accessTime: \(accessTime)") }
            if let modifyTime { changes.append("modifyTime: \(modifyTime)") }
            if let flags { changes.append("permissions: \(flags)") }
            return changes
        }().joined(separator: ", ")

        try await perform(
            with: itemId,
            recording: "Set attributes of \(ref(for: itemId)) to \(changes)"
        ) {
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

        try await perform(
            with: parentId,
            recording:
                "Create symlink from \(ref(for: name, in: parentId)) to \(target)"
        ) {
            try await sftp.createSymlink(
                to: target,
                at: path(for: name, in: parentId)
            )
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

        let ref = try await ref(for: name, in: parentId)
        try await perform(
            with: parentId,
            recording: "Create directory at \(ref)"
        ) {
            do {
                try await sftp.createDirectory(
                    at: path(for: name, in: parentId),
                    mode: flags.mode
                )
            } catch SSHError.sftpError(.fileAlreadyExists, _) {
                switch ifExists {
                case .succeed:
                    logger.info("Directory already exists at \(ref)")
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

        try await perform(
            with: itemId,
            recording:
                "Move \(ref(for: itemId)) to \(ref(for: newName, in: newParentId))"
        ) {
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

        try await perform(
            with: itemId,
            recording: "Remove file \(ref(for: itemId))"
        ) {
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

        try await perform(
            with: itemId,
            recording: "Remove directory \(ref(for: itemId))"
        ) {
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

        let fp = try FileHandle(forReadingFrom: url)
        defer { try? fp.close() }
        let size = try FileManager.default.size(of: url)

        progress.kind = .file
        progress.fileOperationKind = .uploading

        let transfer = await transfers.begin(
            name: name,
            progress: progress
        )
        defer { transfers.end(transfer: transfer) }

        let message: OperationMessage = try await
            "Upload \(ref(for: name, in: parentId))"
        let estimator = ThroughputEstimator(
            progress: progress,
            totalUnitCount: Int64(size),
            reporters: [
                transferProgressReporter(for: transfer),
                loggingProgressReporter(message),
            ]
        )

        let bufferSize = sftp.limits.writeLength(for: chunkSize)
        try await performTransfer(
            with: parentId,
            recording: message,
            estimator: estimator,
            progress: progress
        ) {
            try await sftp.withSftpFile(
                at: path(for: name, in: parentId),
                accessType: .writeOnly,
                mode: flags.mode
            ) { file in
                try await file.withAsyncWriter { writer in
                    while let data = try fp.read(upToCount: Int(bufferSize)) {
                        if progress.isCancelled {
                            throw CoreError.userCancelled
                        }
                        try await writer.write(data: data)
                        estimator.update(delta: data.count)
                    }
                }
            }
        }

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

        let message: OperationMessage = try await "Download \(ref(for: itemId))"
        let estimator = ThroughputEstimator(
            progress: progress,
            totalUnitCount: Int64(item.size ?? 0),
            reporters: [
                transferProgressReporter(for: transfer),
                loggingProgressReporter(message),
            ]
        )

        let bufferSize = sftp.limits.readLength(for: chunkSize)
        try await performTransfer(
            with: itemId,
            recording: message,
            estimator: estimator,
            progress: progress
        ) {
            try await sftp.withSftpFile(
                at: path(for: itemId),
                accessType: .readOnly
            ) { fp in
                for try await data in fp.stream(bufferSize: bufferSize) {
                    if progress.isCancelled {
                        throw CoreError.userCancelled
                    }
                    try handle.write(contentsOf: data)
                    estimator.update(delta: data.count)
                }
            }
        }

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
            reporters: [loggingProgressReporter("Stream \(slice)")]
        )

        for chunk in slice {
            if progress.isCancelled {
                logger.info("Stream \(slice) cancelled")
                throw CoreError.userCancelled
            }
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
        try await perform(with: itemId) {
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
        try await perform(with: parentId) {
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
        _ work: @Sendable (SFTPFile) async throws -> T
    ) async throws -> T {
        try await perform(with: itemId) {
            try await sftp.withSftpFile(
                at: path(for: itemId),
                accessType: accessType,
                mode: mode,
                perform: work
            )
        }
    }

    private func withDirectory<T: Sendable>(
        for itemId: NSFileProviderItemIdentifier,
        _ work: @Sendable (SFTPDirectory) async throws -> T
    ) async throws -> T {
        try await perform(with: itemId) {
            try await sftp.withDirectory(
                at: path(for: itemId),
                perform: work
            )
        }
    }

    private func withEntries<T: Sendable>(
        of itemId: NSFileProviderItemIdentifier,
        _ work: @Sendable (any SSHItem.Stream) async throws -> T
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
                return try await work(entries)
            }
        } catch CoreError.itemNotFound where itemId == .trashContainer {
            return try await work(SSHItem.EmptyStream())
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
        try await perform(with: parentId) {
            try await sftp.symlinkTarget(
                at: path(for: name, in: parentId)
            )
        }
    }

    private func perform<T>(
        with itemId: NSFileProviderItemIdentifier,
        recording message: OperationMessage? = nil,
        _ work: () async throws -> T
    ) async throws -> T {
        if let message { logger.info(message.debug) }
        do {
            let result = try await work()
            if let message { fileLog.info(message.display) }
            return result
        } catch {
            let mapped = coreError(from: error, itemId: itemId)
            if let message {
                logger.error("Failed: \(message.debug): \(error) -> \(mapped)")
                fileLog.error(message.display, error: mapped)
            }
            if case CoreError.serverUnreachable = mapped {
                await connectionLostHandler()
            }
            throw mapped
        }
    }

    private func performTransfer(
        with itemId: NSFileProviderItemIdentifier,
        recording message: OperationMessage,
        estimator: ThroughputEstimator,
        progress: Progress,
        _ work: () async throws -> Void
    ) async throws {
        logger.info(message.debug)
        do {
            try await perform(with: itemId, work)
            estimator.finalize()
            fileLog.info(message.display, detail: progress.report)
        } catch CoreError.userCancelled {
            logger.info("Cancelled: \(message.debug)")
            fileLog.notice(message.display, detail: "Cancelled")
            throw CoreError.userCancelled
        } catch {
            logger.error("Failed: \(message.debug): \(error)")
            fileLog.error(message.display, detail: error.localizedDescription)
            throw error
        }
    }

    private func coreError(
        from error: any Error,
        itemId: NSFileProviderItemIdentifier
    ) -> any Error {
        guard let error = error as? SSHError else { return error }

        if error.isConnectionFailed
            || error.isClosed
            || error.sftpError == .connectionLost
            || error.sftpError == .noConnection
        {
            logger.error("SSH connection lost: \(error)")
            return CoreError.serverUnreachable
        }

        switch error {
        case .sftpError(.noSuchFile, _):
            return CoreError.itemNotFound(itemId.rawValue)
        case .sftpError(.permissionDenied, _):
            return CoreError.permissionDenied
        case .sftpError(.fileAlreadyExists, _):
            return CoreError.filenameCollision
        case .sftpError(.failure, let message):
            logger.error("SFTP operation failed: \(message)")
            return CoreError.unknown(domain: "SFTP", code: 0, message: message)
        default:
            return error
        }
    }

    private func transferProgressReporter(
        for transfer: Transfer
    ) -> ThrottledProgressReporter {
        ThrottledProgressReporter(
            frequency: TimeInterval(0.2),
            onUpdate: { _ in transfer.update() },
            onFinalize: { _ in transfer.update() }
        )
    }

    private func loggingProgressReporter(
        _ message: OperationMessage
    ) -> ThrottledProgressReporter {
        ThrottledProgressReporter(
            frequency: TimeInterval(1.0),
            onUpdate: {
                logger.debug("\(message.debug): \($0.report)")
            },
            onFinalize: {
                logger.info("Finished: \(message.debug): \($0.report)")
            }
        )
    }
}

struct Ref: CustomStringConvertible {
    enum Anchor {
        case item(id: String)
        case parent(id: String)
    }

    private let path: String
    private let anchor: Anchor

    init(path: String, anchor: Anchor) {
        self.path = path
        self.anchor = anchor
    }

    var display: String {
        "\"\(path)\""
    }

    var description: String {
        switch anchor {
        case .item(let id):
            "Ref(path: \(display), id: \(id))"
        case .parent(let id):
            "Ref(path: \(display), parentId: \(id))"
        }
    }
}

struct OperationMessage: ExpressibleByStringInterpolation {
    final class StringInterpolation: StringInterpolationProtocol {
        var debug = ""
        var display = ""

        init(literalCapacity: Int, interpolationCount: Int) {}

        func appendLiteral(_ s: String) {
            debug += s
            display += s
        }

        func appendInterpolation(_ ref: Ref) {
            debug += ref.description
            display += ref.display
        }

        func appendInterpolation(_ v: some CustomStringConvertible) {
            let s = String(describing: v)
            debug += s
            display += s
        }
    }

    let debug: String
    let display: String

    init(stringLiteral v: String) {
        debug = v
        display = v
    }

    init(stringInterpolation i: StringInterpolation) {
        debug = i.debug
        display = i.display
    }
}
