import FileProvider
import Foundation
import SwiftData

private func defaultModelContainer(for domain: NSFileProviderDomain) throws
    -> ModelContainer
{
    let schema = Schema([SSHItem.self])
    guard
        let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier:
                "group.com.kosolabs.SSHadow"
        )
    else {
        throw CocoaError(.fileReadUnknown)
    }

    return try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(
            schema: schema,
            url: groupURL.appendingPathComponent(
                "SSHadowDB-\(domain.identifier.rawValue).sqlite"
            )
        )
    )
}

@ModelActor
public actor SSHItemStore {
    public init(
        domain: NSFileProviderDomain,
        modelContainer: ModelContainer? = nil
    ) throws {
        self.modelContainer =
            try modelContainer ?? defaultModelContainer(for: domain)
        self.modelExecutor = DefaultSerialModelExecutor(
            modelContext: ModelContext(self.modelContainer)
        )
    }

    public func fetch(id: UUID) -> SSHItem? {
        let descriptor = FetchDescriptor<SSHItem>(
            predicate: #Predicate { input in
                input.id == id
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    public func upsert(_ item: SSHItem) throws {
        modelContext.insert(item)
        try modelContext.save()
    }
}
