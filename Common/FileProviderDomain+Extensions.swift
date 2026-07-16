import FileProvider

private let logger = Logger(category: "Domain")

extension NSFileProviderDomain {
    public convenience init(id: UUID, displayName: String) {
        self.init(
            identifier: NSFileProviderDomainIdentifier(id.uuidString),
            displayName: displayName
        )
    }

    public var id: UUID {
        guard let domainId = UUID(uuidString: identifier.rawValue) else {
            logger.fatal("Invalid domain id: \(identifier.rawValue)")
        }
        return domainId
    }

    public var manager: NSFileProviderManager {
        get throws {
            guard let manager = NSFileProviderManager(for: self) else {
                logger.error("Failed to get file provider manager")
                throw NSFileProviderError(.providerNotFound)
            }
            return manager
        }
    }

    public var service: NSFileProviderService {
        get async throws {
            guard
                let service = try await manager.service(
                    named: SSHadow.extensionServiceName,
                    for: .rootContainer
                )
            else {
                logger.error("Failed to get file provider service")
                throw NSFileProviderError(.providerNotFound)
            }
            return service
        }
    }

    public func add() async throws {
        try await NSFileProviderManager.add(self)
        logger.info("Added: \(self)")
    }

    public func remove() async throws {
        try await NSFileProviderManager.remove(self)
        logger.info("Removed: \(self)")
    }

    public override var description: String {
        var fields = [
            "identifier: \(identifier.rawValue)",
            "displayName: \(displayName)",
        ]
        if userEnabled { fields.append("enabled") }
        if isDisconnected { fields.append("disconnected") }
        if isReplicated { fields.append("replicated") }
        if supportsSyncingTrash { fields.append("syncTrash") }
        if !(userInfo?.isEmpty ?? true) { fields.append("userInfo") }
        return "NSFileProviderDomain(\(fields.joined(separator: ", ")))"
    }
}
