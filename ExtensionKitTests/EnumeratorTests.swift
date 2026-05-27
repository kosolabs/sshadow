import Common
import FileProvider
import Synchronization
import Testing

@testable import ExtensionKit

private func enumerate(
    _ enumerator: Enumerator
) async throws -> (
    items: [any NSFileProviderItemProtocol], nextPage: NSFileProviderPage?
) {
    let items = Mutex<[any NSFileProviderItemProtocol]>([])
    let next = try await enumerator.enumerateItems(
        startingAt: NSFileProviderPage.initialPageSortedByName
            as NSFileProviderPage
    ) { batch in
        items.withLock { items in items.append(contentsOf: batch) }
    }
    return (items.withLock { items in items }, next)
}

private func enumerate(
    for itemIdentifier: NSFileProviderItemIdentifier
) async throws -> (
    items: [any NSFileProviderItemProtocol], nextPage: NSFileProviderPage?
) {
    let agent = try await TestData.getAgentClient()
    return try await enumerate(
        Enumerator(agent: agent, itemIdentifier: itemIdentifier)
    )
}

private func enumerate(
    for path: String
) async throws -> (
    items: [any NSFileProviderItemProtocol], nextPage: NSFileProviderPage?
) {
    let agent = try await TestData.getAgentClient()
    let itemIdentifier = try await agent.child(path: path)
    return try await enumerate(
        Enumerator(agent: agent, itemIdentifier: itemIdentifier)
    )
}

@Suite(.serialized)
struct EnumeratorTests {
    @Test func enumerateFolderReturnsChildren() async throws {
        // ls enumerator-list
        let folderPath = "enumerator-list"
        try TestData.removeItem(path: folderPath)
        try TestData.createFolder(path: folderPath)
        try TestData.createFile(path: "\(folderPath)/a.txt", contents: "a")
        try TestData.createFile(path: "\(folderPath)/b.txt", contents: "b")
        try TestData.createFolder(path: "\(folderPath)/sub")

        // Enumerate <id>
        let (items, nextPage) = try await enumerate(for: folderPath)
        let names = Set(items.map(\.filename))

        #expect(names == ["a.txt", "b.txt", "sub"])
        #expect(nextPage == nil)
    }

    @Test func enumerateEmptyFolderReturnsNothing() async throws {
        // ls enumerator-empty
        let folderPath = "enumerator-empty"
        try TestData.removeItem(path: folderPath)
        try TestData.createFolder(path: folderPath)

        // Enumerate <id>
        let (items, nextPage) = try await enumerate(for: folderPath)

        #expect(items.isEmpty)
        #expect(nextPage == nil)
    }

    @Test func enumerateWorkingSetReturnsNothing() async throws {
        let (items, nextPage) = try await enumerate(for: .workingSet)

        #expect(items.isEmpty)
        #expect(nextPage == nil)
    }

    @Test func enumerateTrashContainerWhenAbsentReturnsNothing() async throws {
        // ls .Trash
        try TestData.removeItem(path: ".sshadow")

        // Enumerate .trashContainer
        let (items, nextPage) = try await enumerate(for: .trashContainer)

        #expect(items.isEmpty)
        #expect(nextPage == nil)
    }

    @Test func enumerateTrashContainerWhenPresentReturnsChildren() async throws
    {
        // ls .Trash
        try TestData.removeItem(path: ".sshadow")
        try TestData.createFile(
            path: ".sshadow/trash/trashed.txt",
            contents: "trashed"
        )

        // Enumerate .trashContainer
        let (items, nextPage) = try await enumerate(for: .trashContainer)
        let names = items.map(\.filename)

        #expect(names == ["trashed.txt"])
        #expect(nextPage == nil)
    }

    @Test func sshadowContainerIsHiddenFromRootEnumeration() async throws {
        // ls
        try TestData.createFolder(path: ".sshadow")

        // Enumerate .rootContainer
        let (items, _) = try await enumerate(for: .rootContainer)

        #expect(!items.map(\.id).contains(.sshadowContainer))
        #expect(!items.map(\.filename).contains(".sshadow"))
    }

    @Test func enumerateNonexistentFolderThrows() async throws {
        await #expect(throws: (any Error).self) {
            try await enumerate(
                for: "enumerator-missing-\(UUID().uuidString)"
            )
        }
    }
}
