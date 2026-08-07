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

    public func add() async {
        do {
            try await NSFileProviderManager.add(self)
            logger.info("Domain added: \(self)")
        } catch {
            logger.error("Failed to add domain \(self): \(error)")
        }
    }

    public func remove() async {
        do {
            try await NSFileProviderManager.remove(self)
            logger.info("Domain removed: \(self)")
        } catch {
            logger.error("Failed to remove domain \(self): \(error)")
        }
    }

    public func suspend(
        reason: String,
        options: NSFileProviderManager.DisconnectionOptions = []
    ) async {
        do {
            try await manager.disconnect(reason: reason, options: options)
            logger.info("Sync suspended: \(self)")
        } catch {
            logger.error("Failed to suspend \(self): \(error)")
        }
    }

    public func resume() async {
        do {
            try await manager.reconnect()
            logger.info("Sync resumed: \(self)")
        } catch {
            logger.error("Failed to resume \(self): \(error)")
        }
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
