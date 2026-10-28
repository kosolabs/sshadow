import FileProvider
import Foundation
import Synchronization

package final class FakeMaterializedItems: Sendable {
    private struct State {
        var ids: Set<NSFileProviderItemIdentifier> = []
        var log: [LoggedChange] = []
        var oldestAnchor = 0
        var pageSize = Int.max
        var batchSize = Int.max
        var held = false
        var parked: [@Sendable () -> Void] = []
        var reloads = 0
        var changeEnumerations = 0
        var created = 0
        var invalidated = 0
        var failures = 0
        var evicted: [NSFileProviderItemIdentifier] = []
        var refusesEviction = false
    }

    private let state = Mutex(State())

    package init() {}

    package var reloads: Int { state.withLock { $0.reloads } }
    package var changeEnumerations: Int {
        state.withLock { $0.changeEnumerations }
    }
    package var created: Int { state.withLock { $0.created } }
    package var invalidated: Int { state.withLock { $0.invalidated } }
    package var parkedCount: Int { state.withLock { $0.parked.count } }
    package var evicted: [NSFileProviderItemIdentifier] {
        state.withLock { $0.evicted }
    }

    package func materialize(_ ids: NSFileProviderItemIdentifier...) {
        state.withLock { state in
            for id in ids {
                state.ids.insert(id)
                state.log.append((id, true))
            }
        }
    }

    package func dematerialize(_ ids: NSFileProviderItemIdentifier...) {
        state.withLock { state in
            for id in ids {
                state.ids.remove(id)
                state.log.append((id, false))
            }
        }
    }

    /// Evicts like File Provider, which dematerializes the item.
    package func evict(_ id: NSFileProviderItemIdentifier) throws {
        try state.withLock { state in
            if state.refusesEviction {
                throw NSFileProviderError(.nonEvictableChildren)
            }
            state.evicted.append(id)
            state.ids.remove(id)
            state.log.append((id, false))
        }
    }

    package func refuseEviction() {
        state.withLock { $0.refusesEviction = true }
    }

    package func expireAnchors() {
        state.withLock { $0.oldestAnchor = $0.log.count }
    }

    package func paginate(pageSize: Int, batchSize: Int) {
        state.withLock {
            $0.pageSize = pageSize
            $0.batchSize = batchSize
        }
    }

    package func failNext(_ count: Int) {
        state.withLock { $0.failures = count }
    }

    /// Parks enumerations until `release()`, so a test can act mid-refresh.
    package func hold() {
        state.withLock { $0.held = true }
    }

    package func release() {
        let parked = state.withLock { state in
            state.held = false
            defer { state.parked = [] }
            return state.parked
        }
        for finish in parked { finish() }
    }

    package func enumerator() throws -> any NSFileProviderEnumerator {
        try state.withLock { state in
            if state.failures > 0 {
                state.failures -= 1
                throw NSFileProviderError(.providerNotFound)
            }
            state.created += 1
            return FakeMaterializedEnumerator(store: self)
        }
    }

    fileprivate func enumerateItems(
        for observer: any NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        let offset = Int(page) ?? 0
        let (items, next) = state.withLock { state in
            if offset == 0 { state.reloads += 1 }
            let sorted = state.ids.sorted { $0.rawValue < $1.rawValue }
            let start = min(offset, sorted.count)
            let end = min(sorted.count, start.addingClamped(state.pageSize))
            let next = end < sorted.count ? NSFileProviderPage(end) : nil
            return (sorted[start..<end].map(FakeItem.init), next)
        }
        finish {
            observer.didEnumerate(items)
            observer.finishEnumerating(upTo: next)
        }
    }

    fileprivate func enumerateChanges(
        for observer: any NSFileProviderChangeObserver,
        from anchor: NSFileProviderSyncAnchor
    ) {
        let start = Int(anchor) ?? 0
        let result: Result<LoggedBatch, NSFileProviderError> = state.withLock {
            state in
            state.changeEnumerations += 1
            guard start >= state.oldestAnchor else {
                return .failure(NSFileProviderError(.syncAnchorExpired))
            }
            let end = min(state.log.count, start.addingClamped(state.batchSize))
            return .success(
                LoggedBatch(
                    changes: Array(state.log[start..<end]),
                    end: end,
                    moreComing: end < state.log.count
                )
            )
        }
        finish {
            switch result {
            case .failure(let error):
                observer.finishEnumeratingWithError(error)
            case .success(let batch):
                for change in batch.changes {
                    if change.materialized {
                        observer.didUpdate([FakeItem(change.id)])
                    } else {
                        observer.didDeleteItems(withIdentifiers: [change.id])
                    }
                }
                observer.finishEnumeratingChanges(
                    upTo: NSFileProviderSyncAnchor(batch.end),
                    moreComing: batch.moreComing
                )
            }
        }
    }

    fileprivate var currentAnchor: NSFileProviderSyncAnchor {
        NSFileProviderSyncAnchor(state.withLock { $0.log.count })
    }

    fileprivate func invalidate() {
        state.withLock { $0.invalidated += 1 }
    }

    private func finish(_ callback: @escaping @Sendable () -> Void) {
        let parked = state.withLock { state in
            guard state.held else { return false }
            state.parked.append(callback)
            return true
        }
        if !parked { callback() }
    }
}

private typealias LoggedChange = (
    id: NSFileProviderItemIdentifier, materialized: Bool
)

private struct LoggedBatch {
    let changes: [LoggedChange]
    let end: Int
    let moreComing: Bool
}

private final class FakeMaterializedEnumerator: NSObject,
    NSFileProviderEnumerator
{
    private let store: FakeMaterializedItems

    init(store: FakeMaterializedItems) {
        self.store = store
    }

    func invalidate() {
        store.invalidate()
    }

    func enumerateItems(
        for observer: any NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        store.enumerateItems(for: observer, startingAt: page)
    }

    func enumerateChanges(
        for observer: any NSFileProviderChangeObserver,
        from syncAnchor: NSFileProviderSyncAnchor
    ) {
        store.enumerateChanges(for: observer, from: syncAnchor)
    }

    func currentSyncAnchor(
        completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void
    ) {
        completionHandler(store.currentAnchor)
    }
}

private final class FakeItem: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier = NSFileProviderItemIdentifier.rootContainer
    var filename: String { itemIdentifier.rawValue }

    init(_ itemIdentifier: NSFileProviderItemIdentifier) {
        self.itemIdentifier = itemIdentifier
    }
}

extension Int {
    fileprivate init?(_ page: NSFileProviderPage) {
        self.init(String(decoding: page.rawValue, as: UTF8.self))
    }

    fileprivate init?(_ anchor: NSFileProviderSyncAnchor) {
        self.init(String(decoding: anchor.rawValue, as: UTF8.self))
    }

    fileprivate func addingClamped(_ other: Int) -> Int {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? .max : sum
    }
}

extension NSFileProviderPage {
    fileprivate init(_ offset: Int) {
        self.init(Data(String(offset).utf8))
    }
}

extension NSFileProviderSyncAnchor {
    fileprivate init(_ index: Int) {
        self.init(Data(String(index).utf8))
    }
}
