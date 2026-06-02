import FileProvider

private let logger = Logger(category: "Domain")

extension NSFileProviderDomain {
    public var manager: NSFileProviderManager {
        get throws {
            if let manager = NSFileProviderManager(for: self) {
                return manager
            }
            throw NSFileProviderError(.providerNotFound)
        }
    }

    public func add() async throws {
        try await NSFileProviderManager.add(self)
        logger.info("Added \(self)")
    }

    public func remove() async throws {
        try await NSFileProviderManager.remove(self)
        logger.info("Removed \(self)")
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
