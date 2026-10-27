import Common
import FileProvider
import Foundation
import Ignore
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "Session")

package actor Session {
    package typealias Provider =
        @Sendable (ConnectionConfig, @escaping ConnectionLostHandler)
        async throws(ConnectionError) -> Session
    package typealias Signal = @Sendable () async -> Void
    package typealias ConnectionLostHandler =
        @Sendable (ConnectionError) async -> Void
    package typealias IdleTimeProvider = @Sendable () -> Duration

    private let config: ConnectionConfig
    private let ssh: SSHClient
    private let sftp: SFTPClient
    private let db: DomainDB
    private let groupUrl: URL
    private let changesDetectedHandler: Signal
    private let ignoreRulesChangedHandler: Signal
    private let connectionLostHandler: ConnectionLostHandler
    private let idleTimeProvider: IdleTimeProvider
    private let materializedItems: MaterializedSet.EnumeratorProvider
    private let transfers: Transfers<ContinuousClock>
    private let events: Events<ContinuousClock>

    nonisolated private let log: Events<ContinuousClock>.Logger
    nonisolated private let fileLog: Events<ContinuousClock>.Logger

    private lazy var cache = FileCache(read: read)
    private lazy var ignores = Ignores(filenames: config.ignoreFilenames)
    private lazy var materialized = MaterializedSet(
        enumerator: materializedItems,
        changed: { [weak self] added, removed in
            await self?.materializedChanged(added: added, removed: removed)
        }
    )

    private var watched: [NSFileProviderItemIdentifier: Int] = [:]
    private var schedule: PollSchedule?
    private var pollTask: Task<Void, Never>?
    private(set) var reconcileTask: Task<[Change], any Error>?
    private let gate = ReconcileGate()
    private var changes: [(UInt64, [Change])] = []
    private(set) var anchor: UInt64 = 0

    var limits: Limits {
        Limits(
            maxReadLength: sftp.limits.maxReadLength,
            maxWriteLength: sftp.limits.maxWriteLength
        )
    }

    var ignoreFilenames: [String] {
        config.ignoreFilenames
    }

    var outstanding: Int { gate.operations }

    static func provider(
        domainDb: DomainDB,
        groupUrl: URL,
        signalChanges: @escaping DomainRegistry.DomainSignal,
        retryIgnored: @escaping DomainRegistry.DomainSignal,
        materializedItems: @escaping DomainRegistry.MaterializedEnumerator,
        transfers: Transfers<ContinuousClock>,
        events: Events<ContinuousClock>
    ) -> Provider {
        { config, handler in
            let (ssh, sftp) = try await SSHClient.connect(config: config)
            let session = Session(
                config: config,
                ssh: ssh,
                sftp: sftp,
                db: domainDb,
                groupUrl: groupUrl,
                changesDetectedHandler: { await signalChanges(config) },
                ignoreRulesChangedHandler: { await retryIgnored(config) },
                connectionLostHandler: handler,
                idleTimeProvider: SystemIdle.duration,
                materializedItems: { try materializedItems(config) },
                transfers: transfers,
                events: events
            )
            await session.removeStaleUploads()
            await retryIgnored(config)
            return session
        }
    }

    init(
        config: ConnectionConfig,
        ssh: SSHClient,
        sftp: SFTPClient,
        db: DomainDB,
        groupUrl: URL = SSHadow.groupUrl,
        changesDetectedHandler: @escaping Signal,
        ignoreRulesChangedHandler: @escaping Signal,
        connectionLostHandler: @escaping ConnectionLostHandler,
        idleTimeProvider: @escaping IdleTimeProvider,
        materializedItems: @escaping MaterializedSet.EnumeratorProvider,
        transfers: Transfers<ContinuousClock>,
        events: Events<ContinuousClock>
    ) {
        self.config = config
        self.ssh = ssh
        self.sftp = sftp
        self.db = db
        self.groupUrl = groupUrl
        self.changesDetectedHandler = changesDetectedHandler
        self.ignoreRulesChangedHandler = ignoreRulesChangedHandler
        self.connectionLostHandler = connectionLostHandler
        self.idleTimeProvider = idleTimeProvider
        self.materializedItems = materializedItems
        self.transfers = transfers
        self.events = events

        let source = Event.Source(name: config.name, url: config.url)
        log = events.logger(for: .sync, source: source)
        fileLog = events.logger(for: .file, source: source)
        let dbConfig = db.modelContainer.configurations.first
        let dbPath = dbConfig?.url.path ?? "in-memory"
        logger.notice("SSH connected: \(config), DB: \(dbPath)")
    }
}

// MARK: - Lifecycle

extension Session {
    func close() async {
        await sftp.close()
        await ssh.close()

        logger.notice("SSH disconnected: \(config)")
    }

    func start(pollInterval: Duration?) async {
        await refreshMaterialized()
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
                    logger.debug("Poll interrupted")
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
        guard !gate.isBusy else { return }
        switch schedule.next(
            now: ContinuousClock.now,
            userIdle: idleTimeProvider()
        ) {
        case .pollAll:
            try await pollAll()
        case .pollWatched:
            try await pollWatched()
        case .wait:
            break
        }
    }

    func stop() {
        reconcileTask?.cancel()
        pollTask?.cancel()
        pollTask = nil
    }
}

// MARK: - Lookups

extension Session {
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

    func item(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> Item {
        try await db.item(for: itemId)
    }

    func list(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> [Item] {
        await gate.enter()
        defer { gate.leave() }

        if try await !db.isEnumerated(itemId) {
            try await enumerate(itemId: itemId)
        }
        return try await db.children(of: itemId)
    }

    private func enumerate(itemId: NSFileProviderItemIdentifier) async throws {
        await logger.info("Enumerating \(ref(for: itemId))")
        for sshItem in try await entries(of: itemId) {
            try await upsert(parentId: itemId, sshItem: sshItem)
            logger.info("Enumerate new: \(sshItem)")
        }
        try await db.markEnumerated(itemId)
    }
}

// MARK: - Change Tracking

extension Session {
    func watch(itemId: NSFileProviderItemIdentifier) async {
        guard itemId != .workingSet, itemId != .trashContainer else { return }
        let ref = await ref(for: itemId)

        watched[itemId, default: 0] += 1
        schedule?.recordWatchStarted()

        let newCount = watched[itemId, default: 0]
        logger.info("Watch on \(ref): \(newCount)")
        if newCount == 1 {
            logger.notice("Started watching: \(ref)")
        }
    }

    func unwatch(itemId: NSFileProviderItemIdentifier) async {
        guard itemId != .workingSet, itemId != .trashContainer else { return }
        guard watched[itemId] != nil else { return }
        let ref = await ref(for: itemId)

        guard let count = watched[itemId] else { return }
        if count <= 1 {
            watched.removeValue(forKey: itemId)
        } else {
            watched[itemId] = count - 1
        }

        let newCount = watched[itemId, default: 0]
        logger.info("Unwatch on \(ref): \(newCount)")
        if newCount == 0 {
            logger.notice("Stopped watching: \(ref)")
        }
    }

    func changes(since prevAnchor: UInt64) -> (UInt64, [Change]) {
        let result =
            changes
            .filter { anchor, _ in anchor > prevAnchor }
            .flatMap { _, rowChanges in rowChanges }

        changes.removeAll { anchor, _ in anchor <= prevAnchor }

        return (anchor, result)
    }

    func pollAll() async throws {
        let newChanges = try await gate.reconcile {
            logger.info("Poll: \(config.url), anchor: \(anchor)")

            let reconcileTask = Task { try await reconcileAll() }
            self.reconcileTask = reconcileTask
            defer { self.reconcileTask = nil }
            return try await reconcileTask.value
        }

        schedule?.recordPollAll(at: ContinuousClock.now)
        guard !newChanges.isEmpty else {
            return
        }

        record(newChanges)

        logger.notice(
            "Polled: \(newChanges.count) change(s), anchor: \(anchor)"
        )
        log.notice("Detected \(newChanges.count) change(s) on server")
        await changesDetectedHandler()
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

    func pollWatched() async throws {
        let newChanges: [Change] = try await gate.reconcile {
            guard !watched.isEmpty else { return [] }

            logger.info(
                "Poll: \(config.url), anchor: \(anchor), items: \(watched.keys)"
            )

            let reconcileTask = Task { try await reconcileWatched() }
            self.reconcileTask = reconcileTask
            defer { self.reconcileTask = nil }
            return try await reconcileTask.value
        }

        schedule?.recordPollWatched(at: ContinuousClock.now)
        guard !newChanges.isEmpty else {
            return
        }

        record(newChanges)

        logger.notice(
            "Polled: \(newChanges.count) change(s), anchor: \(anchor), items: \(watched.keys)"
        )
        log.notice("Detected \(newChanges.count) change(s) on server")
        await changesDetectedHandler()
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

    private func reconcile(file dbItem: Item) async throws -> [Change] {
        if let parentId = dbItem.parentId,
            try await ignores.rule(
                ignoring: dbItem.name,
                in: db.path(for: parentId),
                isDirectory: dbItem.kind.isDirectory
            ) != nil
        {
            return []
        }

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

    private func reconcile(folder: Item) async throws -> ([Change], [Item]) {
        var changes: [Change] = []
        var remainder: [Item] = []

        let dbItems = try await Dictionary(
            uniqueKeysWithValues: db.children(of: folder.id).map {
                ($0.name, $0)
            }
        )

        var sshItems: [String: SSHItem] = [:]
        for sshItem in try await entries(of: folder.id) {
            sshItems[sshItem.name] = sshItem
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

        let dir = try await db.path(for: folder.id)
        for (name, dbItem) in dbItems where sshItems[name] == nil {
            guard
                ignores.rule(
                    ignoring: dbItem.name,
                    in: dir,
                    isDirectory: dbItem.kind.isDirectory
                ) == nil
            else { continue }
            logger.info("Reconcile deleted: \(dbItem)")
            try await db.remove(dbItem.id)
            await cache.invalidate(dbItem.id)
            changes.append(.delete(itemId: dbItem.rawId))
        }

        return (changes, remainder)
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
        case .folder, .package:
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
}

// MARK: - Materialized Items

extension Session {
    @discardableResult
    func refreshMaterialized() async -> Task<Void, Never> {
        await materialized.refresh()
    }

    private func materializedChanged(
        added: Set<NSFileProviderItemIdentifier>,
        removed: Set<NSFileProviderItemIdentifier>
    ) async {
        for itemId in added {
            await logger.info("Materialized: \(ref(for: itemId))")
        }
        for itemId in removed {
            await logger.info("Dematerialized: \(ref(for: itemId))")
        }
    }
}

// MARK: - Mutations

extension Session {
    @discardableResult
    func setAttributes(
        for itemId: NSFileProviderItemIdentifier,
        flags: Item.Flags? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil,
        snapshot: IgnoreSnapshot?
    ) async throws -> Item {
        await gate.enter()
        defer { gate.leave() }

        let ref = await ref(for: itemId)
        if let rule = try await rule(for: itemId, snapshot: snapshot) {
            skip("Skip set attributes of \(ref)", by: rule)
            throw CoreError.excludedFromSync
        }

        let changes = {
            var changes: [String] = []
            if let accessTime { changes.append("accessTime: \(accessTime)") }
            if let modifyTime { changes.append("modifyTime: \(modifyTime)") }
            if let flags { changes.append("permissions: \(flags)") }
            return changes
        }().joined(separator: ", ")

        try await perform(
            with: itemId,
            recording: "Set attributes of \(ref) to \(changes)"
        ) {
            try await sftp.setAttributes(
                at: path(for: itemId),
                followSymlinks: false,
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
        target: String,
        snapshot: IgnoreSnapshot?
    ) async throws -> Item {
        await gate.enter()
        defer { gate.leave() }

        let ref = await ref(for: name, in: parentId)
        if let rule = try await rule(
            for: name,
            in: parentId,
            isDirectory: false,
            snapshot: snapshot
        ) {
            skip("Skip create symlink at \(ref)", by: rule)
            throw CoreError.excludedFromSync
        }

        try await perform(
            with: parentId,
            recording: "Create symlink from \(ref) to \(target)"
        ) {
            try await sftp.makeSymlink(
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
        ifExists: OnExists = .fail,
        snapshot: IgnoreSnapshot?
    ) async throws -> Item {
        await gate.enter()
        defer { gate.leave() }

        let ref = await ref(for: name, in: parentId)
        if let rule = try await rule(
            for: name,
            in: parentId,
            isDirectory: true,
            snapshot: snapshot
        ) {
            skip("Skip create directory at \(ref)", by: rule)
            throw CoreError.excludedFromSync
        }

        try await perform(
            with: parentId,
            recording: "Create directory at \(ref)"
        ) {
            try await sftp.makeDirectory(
                at: path(for: name, in: parentId),
                mode: flags.mode,
                ifExists: ifExists
            )
        }
        let item = try await record(
            name,
            in: parentId,
            kind: .init(directoryNamed: name)
        )
        try await db.markEnumerated(item.id)
        return item
    }

    @discardableResult
    func move(
        _ itemId: NSFileProviderItemIdentifier,
        to newParentId: NSFileProviderItemIdentifier,
        name newName: String,
        snapshot: IgnoreSnapshot?
    ) async throws -> Item {
        await gate.enter()
        defer { gate.leave() }

        let from = await ref(for: itemId)
        let to = await ref(for: newName, in: newParentId)
        let rule =
            newParentId == .trashContainer
            ? try await rule(for: itemId, snapshot: snapshot)
            : try await rule(
                for: newName,
                in: newParentId,
                isDirectory: db.item(for: itemId).kind.isDirectory,
                snapshot: snapshot
            )
        if let rule {
            skip("Skip move of \(from) to \(to)", by: rule)
            throw CoreError.excludedFromSync
        }

        let oldPath = try await path(for: itemId)
        let newPath = try await path(for: newName, in: newParentId)

        try await perform(with: itemId, recording: "Move \(from) to \(to)") {
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
        for itemId: NSFileProviderItemIdentifier,
        snapshot: IgnoreSnapshot?
    ) async throws {
        await gate.enter()
        defer { gate.leave() }

        guard try await !forgetIfIgnored(itemId, snapshot: snapshot) else {
            return
        }

        let ref = await ref(for: itemId)
        try await perform(with: itemId, recording: "Remove file \(ref)") {
            try await sftp.removeFile(at: path(for: itemId))
        }
        try await refresh(db.parent(of: itemId).id)
        try await db.remove(itemId)
    }

    func removeDirectory(
        for itemId: NSFileProviderItemIdentifier,
        snapshot: IgnoreSnapshot?
    ) async throws {
        await gate.enter()
        defer { gate.leave() }

        guard try await !forgetIfIgnored(itemId, snapshot: snapshot) else {
            return
        }

        try await perform(
            with: itemId,
            recording: "Remove directory \(ref(for: itemId))"
        ) {
            try await sftp.removeDirectoryRecursively(at: path(for: itemId))
        }
        try await refresh(db.parent(of: itemId).id)
        try await db.remove(itemId)
    }

    private func forgetIfIgnored(
        _ itemId: NSFileProviderItemIdentifier,
        snapshot: IgnoreSnapshot?
    ) async throws -> Bool {
        guard let rule = try await rule(for: itemId, snapshot: snapshot)
        else { return false }
        await skip("Skip remove of \(ref(for: itemId))", by: rule)
        try await db.remove(itemId)
        await cache.invalidate(itemId)
        return true
    }
}

// MARK: - Ignore Rules

extension Session {
    private func rule(
        for itemId: NSFileProviderItemIdentifier,
        snapshot: IgnoreSnapshot?
    ) async throws -> Rule? {
        let item = try await db.item(for: itemId)
        guard let parentId = item.parentId else { return nil }
        return try await rule(
            for: item.name,
            in: parentId,
            isDirectory: item.kind.isDirectory,
            snapshot: snapshot
        )
    }

    private func rule(
        for name: String,
        in parentId: NSFileProviderItemIdentifier,
        isDirectory: Bool,
        snapshot: IgnoreSnapshot?
    ) async throws -> Rule? {
        guard let snapshot else { return nil }
        try await refreshIgnores(from: snapshot)

        return ignores.rule(
            ignoring: name,
            in: try await db.path(for: parentId),
            isDirectory: isDirectory
        )
    }

    private func skip(_ message: LogMessage, by rule: Rule) {
        logger.info("\(message.debug): \(rule.source)")
        fileLog.info(message.display, detail: rule.source)
    }

    private func refreshIgnores(from snapshot: IgnoreSnapshot) async throws {
        var folders: [IgnoreFolder] = []
        for folder in snapshot {
            if ignores.knows(folder.path) {
                folders.append(folder)
            } else {
                folders.append(try await resolved(folder))
            }
        }
        await ignoresChanged(ignores.update(folders), poll: true)
    }

    private func resolved(_ folder: IgnoreFolder) async throws -> IgnoreFolder {
        var files: [IgnoreFile] = []
        for file in folder.files {
            guard file.content == .unresolved else {
                files.append(file)
                continue
            }
            if let file = try await readIgnoreFile(file.name, in: folder.path) {
                files.append(file)
            }
        }
        return IgnoreFolder(path: folder.path, files: files)
    }

    private func refreshIgnores(
        from listing: [SFTPAttributes],
        in dir: String
    ) async throws {
        guard !config.ignoreFilenames.isEmpty, !dir.hasPrefix(".sshadow/")
        else { return }

        try await loadIgnores(in: ancestors(of: dir))
        let folder = IgnoreFolder(
            path: dir,
            files: try await listedIgnoreFiles(in: listing, at: dir)
        )
        await ignoresChanged(ignores.update([folder]), poll: false)
    }

    private func loadIgnores(in dirs: [String]) async throws {
        var folders: [IgnoreFolder] = []
        for dir in dirs where !ignores.knows(dir) {
            var files: [IgnoreFile] = []
            for name in config.ignoreFilenames {
                if let file = try await readIgnoreFile(name, in: dir) {
                    files.append(file)
                }
            }
            folders.append(IgnoreFolder(path: dir, files: files))
        }
        ignores.update(folders)
    }

    private func listedIgnoreFiles(
        in listing: [SFTPAttributes],
        at dir: String
    ) async throws -> [IgnoreFile] {
        var files: [IgnoreFile] = []
        for attrs in listing {
            guard attrs.type != .directory, let name = attrs.name,
                config.ignoreFilenames.contains(name)
            else { continue }
            if ignores.isCurrent(name, in: dir, at: attrs.ignoreFileVersion) {
                files.append(IgnoreFile(name: name, content: .unresolved))
            } else if let file = try await readIgnoreFile(name, in: dir) {
                files.append(file)
            }
        }
        return files
    }

    private func ignoresChanged(_ dirs: [String], poll: Bool) async {
        guard !dirs.isEmpty else { return }
        for dir in dirs {
            logger.info("Ignore rules changed in \(dir.isEmpty ? "/" : dir)")
        }
        if poll { schedule?.requestPollAll() }
        await ignoreRulesChangedHandler()
    }

    private func readIgnoreFile(
        _ name: String,
        in dir: String
    ) async throws -> IgnoreFile? {
        let path = subpath(name, in: dir)
        return try await perform(with: .rootContainer) {
            do {
                logger.info("Read \"\(path)\"")
                return try await sftp.withSftpFile(
                    at: config.path(for: path),
                    accessType: .readOnly
                ) { file in
                    let data = try await file.read()
                    let version = try await file.attributes().ignoreFileVersion
                    return IgnoreFile(
                        name: name,
                        content: .loaded(
                            String(decoding: data, as: UTF8.self),
                            version: version
                        )
                    )
                }
            } catch SSHError.sftpError(.noSuchFile, _) {
                return nil
            }
        }
    }
}

// MARK: - Transfers

extension Session {
    func upload(
        _ name: String,
        to parentId: NSFileProviderItemIdentifier,
        file url: URL,
        chunkSize: UInt64 = SFTPLimits.defaultBufferSize,
        snapshot: IgnoreSnapshot?,
        progress: Progress
    ) async throws -> Item {
        await gate.enter()
        defer { gate.leave() }

        let ref = await ref(for: name, in: parentId)
        let manifest = try Manifest(from: url)
        if let rule = try await rule(
            for: name,
            in: parentId,
            isDirectory: manifest.root.kind == .folder,
            snapshot: snapshot
        ) {
            skip("Skip upload of \(ref)", by: rule)
            throw CoreError.excludedFromSync
        }

        progress.kind = .file
        progress.fileOperationKind = .uploading

        let transfer = await transfers.begin(
            name: name,
            progress: progress
        )
        defer { transfers.end(transfer: transfer) }

        if let itemId = try? await child(of: parentId, name: name) {
            await cache.invalidate(itemId)
        }

        let message: LogMessage = "Upload \(ref)"
        let estimator = ThroughputEstimator(
            progress: progress,
            totalUnitCount: Int64(manifest.totalSize()),
            reporters: [
                transferProgressReporter(for: transfer),
                loggingProgressReporter(message),
            ]
        )

        try await performTransfer(
            with: parentId,
            recording: message,
            estimator: estimator,
            progress: progress
        ) {
            let target = try await path(for: name, in: parentId)
            let kind = manifest.root.kind
            let staged = stagingName()
            let writeStaged = {
                try await self.write(
                    manifest,
                    from: url,
                    to: self.stagingPath(staged),
                    chunkSize: chunkSize,
                    estimator: estimator,
                    progress: progress
                )
            }
            do {
                do {
                    try await writeStaged()
                } catch SSHError.sftpError(.noSuchFile, _) {
                    logger.info("Uploads folder doesn't exist, creating")
                    await removeStaged(staged, kind: kind)
                    try await sftp.createDirectoryRecursively(at: stagingPath)
                    try await writeStaged()
                }
                try await install(staged, at: target, kind: kind)
            } catch {
                await removeStaged(staged, kind: kind)
                switch coreError(from: error, itemId: parentId) {
                case CoreError.userCancelled, CoreError.serverUnreachable:
                    throw error
                default:
                    logger.error("Failed to upload \(target): \(error)")
                    throw CoreError.cannotSynchronize
                }
            }
        }

        let kind: Item.Kind =
            manifest.root.kind == .folder ? .init(directoryNamed: name) : .file
        let item = try await record(name, in: parentId, kind: kind)
        await cache.invalidate(item.id)
        return item
    }

    private func install(
        _ staged: String,
        at target: String,
        kind: Manifest.Entry.Kind
    ) async throws {
        guard kind == .folder, try await sftp.isDirectory(at: target) else {
            try await sftp.move(from: stagingPath(staged), to: target)
            return
        }
        let old = stagingName()
        try await sftp.move(from: target, to: stagingPath(old))
        do {
            try await sftp.move(from: stagingPath(staged), to: target)
        } catch {
            try? await sftp.move(from: stagingPath(old), to: target)
            throw error
        }
        await removeStaged(old, kind: kind)
    }

    private func write(
        _ manifest: Manifest,
        from url: URL,
        to root: String,
        chunkSize: UInt64,
        estimator: ThroughputEstimator,
        progress: Progress
    ) async throws {
        let bufferSize = sftp.limits.writeLength(for: chunkSize)
        for entry in manifest.entries {
            if progress.isCancelled { throw CoreError.userCancelled }
            let remotePath = entry.path(under: root)
            switch entry.kind {
            case .folder:
                try await sftp.makeDirectory(
                    at: remotePath,
                    mode: entry.mode
                )
            case .file:
                let fp = try FileHandle(
                    forReadingFrom: entry.url(under: url)
                )
                defer { try? fp.close() }
                try await sftp.writeFile(
                    at: remotePath,
                    mode: entry.mode
                ) { file in
                    try await file.withAsyncWriter { writer in
                        while let data = try fp.read(
                            upToCount: Int(bufferSize)
                        ) {
                            if progress.isCancelled {
                                throw CoreError.userCancelled
                            }
                            try await writer.write(data: data)
                            estimator.update(delta: data.count)
                        }
                    }
                }
            case .symlink(let target):
                try await sftp.makeSymlink(to: target, at: remotePath)
            }
        }
    }

    func download(
        itemId: NSFileProviderItemIdentifier,
        chunkSize: UInt64 = SFTPLimits.defaultBufferSize,
        progress: Progress
    ) async throws -> (URL, Item) {
        await gate.enter()
        defer { gate.leave() }

        let item = try await item(for: itemId)
        let url = groupUrl.appending(path: itemId.rawValue)
        let manifest = try await manifest(for: item)

        let fm = FileManager.default
        if fm.fileExists(atPath: url.path(percentEncoded: false)) {
            try fm.removeItem(at: url)
        }

        progress.kind = .file
        progress.fileOperationKind = .downloading

        let transfer = await transfers.begin(
            name: item.name,
            progress: progress
        )
        defer { transfers.end(transfer: transfer) }

        let message: LogMessage = await "Download \(ref(for: itemId))"
        let estimator = ThroughputEstimator(
            progress: progress,
            totalUnitCount: Int64(manifest.totalSize()),
            reporters: [
                transferProgressReporter(for: transfer),
                loggingProgressReporter(message),
            ]
        )

        try await performTransfer(
            with: itemId,
            recording: message,
            estimator: estimator,
            progress: progress
        ) {
            let root = try await path(for: itemId)
            let bufferSize = sftp.limits.readLength(for: chunkSize)

            for entry in manifest.entries {
                if progress.isCancelled { throw CoreError.userCancelled }
                let localUrl = entry.url(under: url)
                switch entry.kind {
                case .folder:
                    try fm.createDirectory(
                        at: localUrl,
                        withIntermediateDirectories: false,
                        attributes: [.posixPermissions: entry.mode]
                    )
                case .file:
                    let handle = try FileHandle(for: localUrl, mode: entry.mode)
                    defer { try? handle.close() }
                    try await sftp.withSftpFile(
                        at: entry.path(under: root),
                        accessType: .readOnly
                    ) { fp in
                        for try await data in fp.stream(bufferSize: bufferSize)
                        {
                            if progress.isCancelled {
                                throw CoreError.userCancelled
                            }
                            try handle.write(contentsOf: data)
                            estimator.update(delta: data.count)
                        }
                    }
                case .symlink(let target):
                    try fm.createSymbolicLink(
                        atPath: localUrl.path(percentEncoded: false),
                        withDestinationPath: target
                    )
                }
            }
        }

        return (url, item)
    }

    private func manifest(for item: Item) async throws -> Manifest {
        guard item.kind.isDirectory else {
            let kind = Manifest.Entry.Kind.file(size: item.size ?? 0)
            return try Manifest(entries: [
                Manifest.Entry(path: "", kind: kind)
            ])
        }
        return try await perform(with: item.id) {
            try await Manifest(from: path(for: item.id), sftp: sftp)
        }
    }

    func stream(
        itemId: NSFileProviderItemIdentifier,
        range: Range<UInt64>,
        progress: Progress
    ) async throws -> (URL, Range<UInt64>) {
        await gate.enter()
        defer { gate.leave() }

        let item = try await item(for: itemId)
        let file = File(item: item)
        let url = groupUrl.appending(path: "\(itemId.rawValue)")
        let slice = file.slice(for: range)

        logger.info("Stream \(range) -> \(slice) into \(url)")
        let handle = try FileHandle(for: url)
        defer { try? handle.close() }

        progress.kind = .file
        progress.fileOperationKind = .downloading

        let estimator = ThroughputEstimator(
            progress: progress,
            totalUnitCount: Int64(slice.byteRange.length),
            reporters: [loggingProgressReporter("Stream \(slice)")]
        )
        defer { estimator.finalize() }

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

        return (url, slice.byteRange)
    }

    func removeStaleUploads(
        olderThan age: TimeInterval = 24 * 60 * 60
    ) async {
        let cutoff = Date.now.addingTimeInterval(-age)
        let stale: [(String, Manifest.Entry.Kind)]
        do {
            stale = try await sftp.withDirectory(at: stagingPath) { dir in
                var stale: [(String, Manifest.Entry.Kind)] = []
                for try await attrs in dir {
                    guard let name = attrs.name,
                        let modifyTime = attrs.modifyTime,
                        modifyTime < cutoff
                    else { continue }
                    let kind: Manifest.Entry.Kind =
                        attrs.type == .directory ? .folder : .file(size: 0)
                    stale.append((name, kind))
                }
                return stale
            }
        } catch SSHError.sftpError(.noSuchFile, _) {
            return
        } catch {
            logger.error("Failed to list \(stagingPath): \(error)")
            return
        }
        for (name, kind) in stale {
            await removeStaged(name, kind: kind)
        }
    }

    private func removeStaged(
        _ name: String,
        kind: Manifest.Entry.Kind
    ) async {
        let path = stagingPath(name)
        do {
            if kind == .folder {
                try await sftp.removeDirectoryRecursively(at: path)
            } else {
                try await sftp.removeFile(at: path)
            }
            logger.notice("Removed staged upload: \(path)")
        } catch SSHError.sftpError(.noSuchFile, _) {
            return
        } catch {
            logger.error("Failed to remove staged upload \(path): \(error)")
        }
    }

    private func stagingName() -> String {
        UUID().uuidString
    }

    private var stagingPath: String {
        config.path(for: ".sshadow/uploads")
    }

    private func stagingPath(_ name: String) -> String {
        "\(stagingPath)/\(name)"
    }

    private func performTransfer(
        with itemId: NSFileProviderItemIdentifier,
        recording message: LogMessage,
        estimator: ThroughputEstimator,
        progress: Progress,
        _ work: () async throws -> Void
    ) async throws {
        logger.info(message.debug)
        defer { estimator.finalize() }
        do {
            try await perform(with: itemId, work)
            fileLog.info(message.display, detail: progress.report)
        } catch CoreError.userCancelled {
            logger.info("Cancelled: \(message.debug)")
            fileLog.info(message.display, detail: "Cancelled")
            throw CoreError.userCancelled
        } catch {
            logger.error("Failed: \(message.debug): \(error)")
            fileLog.error(message.display, detail: error.localizedDescription)
            throw error
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
        _ message: LogMessage
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

// MARK: - Shared Plumbing

extension Session {
    func ref(for itemId: NSFileProviderItemIdentifier) async -> Ref {
        Ref(
            path: try? await db.path(for: itemId),
            anchor: .item(id: itemId.rawValue)
        )
    }

    func ref(
        for name: String,
        in parentId: NSFileProviderItemIdentifier
    ) async -> Ref {
        Ref(
            path: try? await db.path(for: name, in: parentId),
            anchor: .parent(id: parentId.rawValue)
        )
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
            size: attrs.itemSize,
            flags: .from(attrs.permissions),
            accessTime: attrs.accessTime,
            modifyTime: attrs.modifyTime,
            createTime: attrs.createTime
        )
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

    private func refresh(_ itemId: NSFileProviderItemIdentifier) async throws {
        let attrs = try await attributes(for: itemId)
        try await db.refresh(
            itemId,
            size: attrs.itemSize,
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

    private func entries(
        of itemId: NSFileProviderItemIdentifier
    ) async throws -> [SSHItem] {
        let listing: [SFTPAttributes]
        do {
            listing = try await withDirectory(for: itemId) { dir in
                var listing: [SFTPAttributes] = []
                for try await attrs in dir { listing.append(attrs) }
                return listing
            }
        } catch CoreError.itemNotFound where itemId == .trashContainer {
            return []
        }

        let dir = try await db.path(for: itemId)
        try await refreshIgnores(from: listing, in: dir)

        var entries: [SSHItem] = []
        for attrs in listing {
            guard let name = attrs.name else { continue }
            if itemId == .rootContainer, name == ".sshadow" { continue }
            let isDirectory = attrs.type == .directory
            if ignores.rule(ignoring: name, in: dir, isDirectory: isDirectory)
                != nil
            {
                continue
            }
            entries.append(
                try await sshItem(for: name, in: itemId, from: attrs)
            )
        }
        return entries
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

    private func sshItem(
        for name: String,
        in parentId: NSFileProviderItemIdentifier,
        from attrs: SFTPAttributes
    ) async throws -> SSHItem {
        let kind: Item.Kind =
            switch attrs.type {
            case .directory:
                .init(directoryNamed: name)
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
            size: attrs.itemSize,
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

    private func perform<T>(
        with itemId: NSFileProviderItemIdentifier,
        recording message: LogMessage? = nil,
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
                await connectionLostHandler(ConnectionError(from: error))
            }
            throw mapped
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
}
