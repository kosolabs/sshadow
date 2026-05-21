import FileProvider

private let logger = Logger(category: "Domain")

extension NSFileProviderDomain {
    public func add() async throws {
        try await NSFileProviderManager.add(self)
        logger.info("Added \(self)")
    }

    public func remove() async throws {
        try await NSFileProviderManager.remove(self)
        logger.info("Removed \(self)")
    }

    public func disconnect() async throws {
        guard let manager = NSFileProviderManager(for: self) else {
            logger.error("No manager for \(self)")
            return
        }
        try await manager.disconnect(
            reason: "SSHadow needs to be running in order to sync this volume.",
            options: .temporary
        )
        logger.info("Disconnected \(self)")
    }

    public func reconnect() async throws {
        guard let manager = NSFileProviderManager(for: self) else {
            logger.error("No manager for \(self)")
            return
        }
        try await manager.reconnect()
        logger.info("Reconnected \(self)")
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
