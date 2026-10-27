import Common
import FileProvider
import Synchronization

private let logger = Logger(category: "MaterializedSet")

actor MaterializedSet {
    typealias EnumeratorProvider =
        @Sendable () throws -> any NSFileProviderEnumerator
    typealias ChangeHandler =
        @Sendable (
            _ added: Set<NSFileProviderItemIdentifier>,
            _ removed: Set<NSFileProviderItemIdentifier>
        ) async -> Void

    private let makeEnumerator: EnumeratorProvider
    private let changed: ChangeHandler

    private(set) var ids: Set<NSFileProviderItemIdentifier> = []
    private var anchor: NSFileProviderSyncAnchor?
    private var refreshTask: Task<Void, Never>?
    private var stale = false

    init(
        enumerator: @escaping EnumeratorProvider,
        changed: @escaping ChangeHandler
    ) {
        self.makeEnumerator = enumerator
        self.changed = changed
    }

    @discardableResult
    func refresh() -> Task<Void, Never> {
        stale = true
        if let refreshTask { return refreshTask }
        let task = Task { await drain() }
        refreshTask = task
        return task
    }

    private func drain() async {
        while stale {
            stale = false
            do {
                try await update()
            } catch {
                logger.error("Failed to refresh materialized set: \(error)")
            }
        }
        refreshTask = nil
    }

    private func update() async throws {
        let enumerator = try makeEnumerator()
        defer { enumerator.invalidate() }

        if let anchor {
            do {
                try await applyChanges(from: anchor, of: enumerator)
                return
            } catch let error as NSFileProviderError
                where error.code == .syncAnchorExpired
            {
                logger.info("Materialized set anchor expired, reloading")
            }
        }
        try await reload(from: enumerator)
    }

    private func applyChanges(
        from anchor: NSFileProviderSyncAnchor,
        of enumerator: any NSFileProviderEnumerator
    ) async throws {
        var batch = ChangeBatch(anchor: anchor, moreComing: true)
        while batch.moreComing {
            batch = try await enumerator.changes(from: batch.anchor)
            let before = ids
            ids.formUnion(batch.updated)
            ids.subtract(batch.deleted)
            self.anchor = batch.anchor
            await report(since: before)
        }
    }

    private func reload(
        from enumerator: any NSFileProviderEnumerator
    ) async throws {
        let anchor = await enumerator.currentAnchor()
        let loaded = try await enumerator.allItemIds()
        let before = ids
        ids = loaded
        self.anchor = anchor
        logger.info("Loaded materialized set: \(loaded.count) item(s)")
        await report(since: before)
    }

    private func report(since before: Set<NSFileProviderItemIdentifier>) async {
        let added = ids.subtracting(before)
        let removed = before.subtracting(ids)
        guard !added.isEmpty || !removed.isEmpty else { return }
        await changed(added, removed)
    }
}

private struct ChangeBatch {
    var updated: Set<NSFileProviderItemIdentifier> = []
    var deleted: Set<NSFileProviderItemIdentifier> = []
    var anchor: NSFileProviderSyncAnchor
    var moreComing: Bool
}

extension NSFileProviderEnumerator {
    fileprivate func currentAnchor() async -> NSFileProviderSyncAnchor? {
        await withCheckedContinuation { continuation in
            guard let currentSyncAnchor else {
                continuation.resume(returning: nil)
                return
            }
            currentSyncAnchor { continuation.resume(returning: $0) }
        }
    }

    fileprivate func allItemIds() async throws -> Set<
        NSFileProviderItemIdentifier
    > {
        var ids: Set<NSFileProviderItemIdentifier> = []
        var page: NSFileProviderPage? = NSFileProviderPage(Data())
        while let current = page {
            let observer = ItemsObserver()
            page = try await withCheckedThrowingContinuation { continuation in
                observer.continuation = continuation
                enumerateItems(for: observer, startingAt: current)
            }
            ids.formUnion(observer.ids.withLock { $0 })
        }
        return ids
    }

    fileprivate func changes(
        from anchor: NSFileProviderSyncAnchor
    ) async throws -> ChangeBatch {
        guard let enumerateChanges else {
            throw NSFileProviderError(.syncAnchorExpired)
        }
        let observer = ChangesObserver()
        let (next, moreComing) = try await withCheckedThrowingContinuation {
            continuation in
            observer.continuation = continuation
            enumerateChanges(observer, anchor)
        }
        return observer.batch.withLock {
            ChangeBatch(
                updated: $0.updated,
                deleted: $0.deleted,
                anchor: next,
                moreComing: moreComing
            )
        }
    }
}

private final class ItemsObserver: NSObject,
    NSFileProviderEnumerationObserver, @unchecked Sendable
{
    let ids = Mutex<Set<NSFileProviderItemIdentifier>>([])
    var continuation: CheckedContinuation<NSFileProviderPage?, any Error>?

    func didEnumerate(_ updatedItems: [any NSFileProviderItemProtocol]) {
        ids.withLock { ids in
            for item in updatedItems { ids.insert(item.itemIdentifier) }
        }
    }

    func finishEnumerating(upTo nextPage: NSFileProviderPage?) {
        continuation?.resume(returning: nextPage)
        continuation = nil
    }

    func finishEnumeratingWithError(_ error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private final class ChangesObserver: NSObject, NSFileProviderChangeObserver,
    @unchecked Sendable
{
    let batch = Mutex(
        (
            updated: Set<NSFileProviderItemIdentifier>(),
            deleted: Set<NSFileProviderItemIdentifier>()
        )
    )
    var continuation:
        CheckedContinuation<(NSFileProviderSyncAnchor, Bool), any Error>?

    func didUpdate(_ updatedItems: [any NSFileProviderItemProtocol]) {
        batch.withLock { batch in
            for item in updatedItems {
                batch.updated.insert(item.itemIdentifier)
                batch.deleted.remove(item.itemIdentifier)
            }
        }
    }

    func didDeleteItems(
        withIdentifiers deletedItemIdentifiers: [NSFileProviderItemIdentifier]
    ) {
        batch.withLock { batch in
            for id in deletedItemIdentifiers {
                batch.deleted.insert(id)
                batch.updated.remove(id)
            }
        }
    }

    func finishEnumeratingChanges(
        upTo anchor: NSFileProviderSyncAnchor,
        moreComing: Bool
    ) {
        continuation?.resume(returning: (anchor, moreComing))
        continuation = nil
    }

    func finishEnumeratingWithError(_ error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
