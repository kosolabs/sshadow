import Common
import FileProvider
import Foundation
import Testing

@testable import CoreKit

private final class SpyDomainStore: @unchecked Sendable {
    let domains: [NSFileProviderDomain]

    private let lock = NSLock()
    private var _removed: [UUID] = []
    private var _deleted: [UUID] = []

    init(domains: [NSFileProviderDomain]) {
        self.domains = domains
    }

    var removed: [UUID] {
        lock.withLock { _removed }
    }

    var deleted: [UUID] {
        lock.withLock { _deleted }
    }

    func remove(_ domain: NSFileProviderDomain) {
        lock.withLock { _removed.append(domain.id) }
    }

    func delete(_ id: UUID) {
        lock.withLock { _deleted.append(id) }
    }
}

struct DomainRegistryTests {
    @Test func removeOrphanedDomainsSucceeds() async throws {
        let enabled = NSFileProviderDomain(id: UUID(), displayName: "Enabled")
        let orphan = NSFileProviderDomain(id: UUID(), displayName: "Orphan")
        let store = SpyDomainStore(domains: [enabled, orphan])

        let registry = DomainRegistry(
            sharedUrl: FileManager.default.temporaryDirectory,
            signalEnumerator: { _ in },
            connections: Connections(),
            transfers: Transfers(),
            events: Events(),
            listDomains: { store.domains },
            removeDomain: { store.remove($0) },
            deleteDomainDB: { store.delete($0) }
        )

        await registry.removeOrphanedDomains(enabledIds: [enabled.id])

        #expect(store.removed == [orphan.id])
        #expect(store.deleted == [orphan.id])
    }
}
