import FileProvider
import Synchronization
import TestKit
import Testing

@testable import CoreKit

private let a = NSFileProviderItemIdentifier("a")
private let b = NSFileProviderItemIdentifier("b")
private let c = NSFileProviderItemIdentifier("c")

private final class ChangeRecorder: Sendable {
    typealias Change = (
        added: Set<NSFileProviderItemIdentifier>,
        removed: Set<NSFileProviderItemIdentifier>
    )

    private let recorded = Mutex<[Change]>([])

    var changes: [Change] { recorded.withLock { $0 } }

    func record(
        _ added: Set<NSFileProviderItemIdentifier>,
        _ removed: Set<NSFileProviderItemIdentifier>
    ) {
        recorded.withLock { $0.append((added, removed)) }
    }
}

private func makeSet(
    _ store: FakeMaterializedItems,
    _ recorder: ChangeRecorder
) -> MaterializedSet {
    MaterializedSet(
        enumerator: { try store.enumerator() },
        changed: { recorder.record($0, $1) }
    )
}

private func waitUntilParked(
    _ store: FakeMaterializedItems,
    timeout: Duration = .seconds(10),
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let deadline = ContinuousClock.now + timeout
    while store.parkedCount == 0 {
        guard ContinuousClock.now < deadline else {
            Issue.record(
                "No enumeration parked within \(timeout)",
                sourceLocation: sourceLocation
            )
            return
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}

struct MaterializedSetTests {
    @Test func refreshLoadsMaterializedItems() async throws {
        let store = FakeMaterializedItems()
        let recorder = ChangeRecorder()
        store.materialize(a, b)
        let set = makeSet(store, recorder)

        await set.refresh().value

        #expect(await set.ids == [a, b])
        #expect(recorder.changes.map(\.added) == [[a, b]])
        #expect(recorder.changes.map(\.removed) == [[]])
    }

    @Test func refreshLoadsEveryPage() async throws {
        let store = FakeMaterializedItems()
        store.paginate(pageSize: 1, batchSize: .max)
        store.materialize(a, b, c)
        let set = makeSet(store, ChangeRecorder())

        await set.refresh().value

        #expect(await set.ids == [a, b, c])
    }

    @Test func refreshAppliesChangesSinceLastRefresh() async throws {
        let store = FakeMaterializedItems()
        let recorder = ChangeRecorder()
        store.materialize(a, b)
        let set = makeSet(store, recorder)
        await set.refresh().value

        store.materialize(c)
        store.dematerialize(a)
        await set.refresh().value

        #expect(await set.ids == [b, c])
        #expect(store.reloads == 1)
        #expect(store.changeEnumerations == 1)
        #expect(recorder.changes.map(\.added) == [[a, b], [c]])
        #expect(recorder.changes.map(\.removed) == [[], [a]])
    }

    @Test func refreshAppliesEveryBatchOfChanges() async throws {
        let store = FakeMaterializedItems()
        store.paginate(pageSize: .max, batchSize: 1)
        let set = makeSet(store, ChangeRecorder())
        await set.refresh().value

        store.materialize(a, b, c)
        store.dematerialize(b)
        await set.refresh().value

        #expect(await set.ids == [a, c])
        #expect(store.reloads == 1)
        #expect(store.changeEnumerations == 4)
    }

    @Test func refreshWithoutChangesReportsNothing() async throws {
        let store = FakeMaterializedItems()
        let recorder = ChangeRecorder()
        store.materialize(a)
        let set = makeSet(store, recorder)
        await set.refresh().value

        await set.refresh().value

        #expect(recorder.changes.count == 1)
    }

    @Test func refreshReloadsWhenAnchorExpires() async throws {
        let store = FakeMaterializedItems()
        let recorder = ChangeRecorder()
        store.materialize(a, b)
        let set = makeSet(store, recorder)
        await set.refresh().value

        store.dematerialize(a)
        store.materialize(c)
        store.expireAnchors()
        await set.refresh().value

        #expect(await set.ids == [b, c])
        #expect(store.reloads == 2)
        #expect(recorder.changes.map(\.added) == [[a, b], [c]])
        #expect(recorder.changes.map(\.removed) == [[], [a]])
    }

    @Test func refreshRecoversAfterEnumeratorFails() async throws {
        let store = FakeMaterializedItems()
        store.materialize(a)
        store.failNext(1)
        let set = makeSet(store, ChangeRecorder())

        await set.refresh().value
        #expect(await set.ids == [])

        await set.refresh().value
        #expect(await set.ids == [a])
    }

    @Test func refreshInvalidatesEachEnumerator() async throws {
        let store = FakeMaterializedItems()
        let set = makeSet(store, ChangeRecorder())

        await set.refresh().value
        await set.refresh().value

        #expect(store.created == 2)
        #expect(store.invalidated == 2)
    }

    @Test func refreshesDuringRefreshCoalesce() async throws {
        let store = FakeMaterializedItems()
        store.materialize(a)
        let set = makeSet(store, ChangeRecorder())
        store.hold()
        let first = await set.refresh()
        try await waitUntilParked(store)

        store.materialize(b)
        let second = await set.refresh()
        let third = await set.refresh()
        store.release()
        await first.value

        #expect(first == second)
        #expect(first == third)
        #expect(await set.ids == [a, b])
        #expect(store.reloads == 1)
        #expect(store.changeEnumerations == 1)
    }
}
