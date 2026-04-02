import FileProvider
import Foundation
import SwiftData
import Testing

@testable import Common

private func makeInMemoryContainer() throws -> ModelContainer {
    let schema = Schema([SSHItem.self])
    let config = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(for: schema, configurations: config)
}

private let testDomain = NSFileProviderDomain(
    identifier: NSFileProviderDomainIdentifier("test"),
    displayName: "Test"
)

struct SSHItemTests {
    @Test func initSetsProperties() {
        let id = UUID()
        let parentId = UUID()
        let item = SSHItem(id: id, parentId: parentId, name: "file.txt")

        #expect(item.id == id)
        #expect(item.parentId == parentId)
        #expect(item.name == "file.txt")
    }
}

struct SSHItemStoreTests {
    @Test func upsertAndFetchById() async throws {
        let container = try makeInMemoryContainer()
        let store = try SSHItemStore(
            domain: testDomain,
            modelContainer: container
        )

        let id = UUID()
        let parentId = UUID()
        let item = SSHItem(id: id, parentId: parentId, name: "hello.txt")

        try await store.upsert(item)
        let fetched = await store.fetch(id: id)

        #expect(fetched != nil)
        #expect(fetched?.id == id)
        #expect(fetched?.parentId == parentId)
        #expect(fetched?.name == "hello.txt")
    }

    @Test func fetchReturnsNilForUnknownId() async throws {
        let container = try makeInMemoryContainer()
        let store = try SSHItemStore(
            domain: testDomain,
            modelContainer: container
        )

        let result = await store.fetch(id: UUID())
        #expect(result == nil)
    }

    @Test func upsertMultipleItems() async throws {
        let container = try makeInMemoryContainer()
        let store = try SSHItemStore(
            domain: testDomain,
            modelContainer: container
        )

        let parentId = UUID()
        let id1 = UUID()
        let id2 = UUID()

        try await store.upsert(
            SSHItem(id: id1, parentId: parentId, name: "a.txt")
        )
        try await store.upsert(
            SSHItem(id: id2, parentId: parentId, name: "b.txt")
        )

        let first = await store.fetch(id: id1)
        let second = await store.fetch(id: id2)

        #expect(first?.name == "a.txt")
        #expect(second?.name == "b.txt")
    }

    @Test func upsertDuplicateIdUpdatesExistingItem() async throws {
        let container = try makeInMemoryContainer()
        let store = try SSHItemStore(
            domain: testDomain,
            modelContainer: container
        )

        let id = UUID()
        let parentId = UUID()

        try await store.upsert(
            SSHItem(id: id, parentId: parentId, name: "first.txt")
        )
        try await store.upsert(
            SSHItem(id: id, parentId: parentId, name: "second.txt")
        )

        let fetched = await store.fetch(id: id)
        #expect(fetched?.name == "second.txt")
    }
}
