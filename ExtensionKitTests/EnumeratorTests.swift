import Common
import FileProvider
import Synchronization
import Testing

@testable import ExtensionKit
@testable import AgentKit

extension TestSandbox {
    fileprivate func getEnumerator(
        for name: String
    ) async throws -> Enumerator {
        let client = try await client
        let itemId = try await client.child(name: name)
        return Enumerator(agent: client, itemIdentifier: itemId)
    }

    fileprivate func getEnumerator(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> Enumerator {
        let client = try await client
        return Enumerator(agent: client, itemIdentifier: itemId)
    }
}

extension Enumerator {
    fileprivate func enumerateItems() async throws -> (
        items: [any NSFileProviderItemProtocol], nextPage: NSFileProviderPage?
    ) {
        let items = Mutex<[any NSFileProviderItemProtocol]>([])
        let next = try await enumerateItems(
            startingAt: NSFileProviderPage.initialPageSortedByName
                as NSFileProviderPage
        ) { batch in
            items.withLock { items in items.append(contentsOf: batch) }
        }
        return (items.withLock { items in items }, next)
    }

    fileprivate func currentSyncAnchor() async -> NSFileProviderSyncAnchor? {
        await withCheckedContinuation { continuation in
            currentSyncAnchor { anchor in
                continuation.resume(returning: anchor)
            }
        }
    }
}

@Suite(.serialized)
struct EnumeratorTests {
    @Test func enumerateFolderReturnsChildren() async throws {
        // ls enumerator-list
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "enumerator-list/a.txt")
        try sandbox.createFile(at: "enumerator-list/b.txt")
        try sandbox.createFolder(at: "enumerator-list/sub")
        let enumerator = try await sandbox.getEnumerator(for: "enumerator-list")

        // Enumerate <id>
        let (items, nextPage) = try await enumerator.enumerateItems()
        let names = Set(items.map(\.filename))

        #expect(names == ["a.txt", "b.txt", "sub"])
        #expect(nextPage == nil)
    }

    @Test func enumerateEmptyFolderReturnsNothing() async throws {
        // ls enumerator-empty
        let sandbox = TestSandbox()
        try sandbox.createFolder(at: "enumerator-empty")
        let enumerator = try await sandbox.getEnumerator(
            for: "enumerator-empty"
        )

        // Enumerate <id>
        let (items, nextPage) = try await enumerator.enumerateItems()

        #expect(items.isEmpty)
        #expect(nextPage == nil)
    }

    @Test func enumerateWorkingSetReturnsNothing() async throws {
        let sandbox = TestSandbox()
        let enumerator = try await sandbox.getEnumerator(for: .workingSet)

        // Enumerate .workingSet
        let (items, nextPage) = try await enumerator.enumerateItems()

        #expect(items.isEmpty)
        #expect(nextPage == nil)
    }

    @Test func enumerateTrashContainerWhenAbsentReturnsNothing() async throws {
        // ls .Trash
        let sandbox = TestSandbox()
        let enumerator = try await sandbox.getEnumerator(for: .trashContainer)

        // Enumerate .trashContainer
        let (items, nextPage) = try await enumerator.enumerateItems()

        #expect(items.isEmpty)
        #expect(nextPage == nil)
    }

    @Test func enumerateTrashContainerReturnsChildren() async throws {
        // ls .Trash
        let sandbox = TestSandbox()
        try sandbox.createFile(at: ".sshadow/trash/trashed.txt")
        let enumerator = try await sandbox.getEnumerator(for: .trashContainer)

        // Enumerate .trashContainer
        let (items, nextPage) = try await enumerator.enumerateItems()
        let names = items.map(\.filename)

        #expect(names == ["trashed.txt"])
        #expect(nextPage == nil)
    }

    @Test func sshadowContainerIsHiddenFromRootEnumeration() async throws {
        // ls
        let sandbox = TestSandbox()
        try sandbox.createFile(at: ".sshadow/trash/trashed.txt")
        let enumerator = try await sandbox.getEnumerator(for: .rootContainer)

        // Enumerate .rootContainer
        let (items, _) = try await enumerator.enumerateItems()

        #expect(items.isEmpty)
    }

    @Test func currentSyncAnchorReflectsAgentState() async throws {
        let sandbox = TestSandbox()
        let enumerator = try await Enumerator(
            agent: sandbox.client,
            itemIdentifier: .rootContainer
        )

        let initial = try #require(await enumerator.currentSyncAnchor())
        #expect(initial.value == 0)

        // touch new.txt
        try sandbox.createFolder(at: "new.txt")
        try await sandbox.agent.poll(domainId: sandbox.id)

        let advanced = try #require(await enumerator.currentSyncAnchor())
        #expect(advanced.value == 1)
    }
}
