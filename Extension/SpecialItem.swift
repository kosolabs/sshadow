import Common
import FileProvider
import SwiftLibSSH
import UniformTypeIdentifiers

public class SpecialItem: NSObject, NSFileProviderItem {
    private let logger: Logger
    public let itemIdentifier: NSFileProviderItemIdentifier

    init(
        domainName: String,
        itemIdentifier: NSFileProviderItemIdentifier,
    ) {
        logger = Logger(category: "Item.\(domainName)")
        logger.debug("init: \(itemIdentifier.rawValue)")
        self.itemIdentifier = itemIdentifier
    }

    public var parentItemIdentifier: NSFileProviderItemIdentifier {
        return .rootContainer
    }

    public var capabilities: NSFileProviderItemCapabilities {
        return [
            .allowsReading, .allowsWriting, .allowsRenaming, .allowsReparenting,
            .allowsTrashing, .allowsDeleting,
        ]
    }

    public var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(
            contentVersion: "a content version".data(using: .utf8)!,
            metadataVersion: "a metadata version".data(using: .utf8)!
        )
    }

    public var filename: String {
        return itemIdentifier.rawValue
    }

    public var contentType: UTType {
        .folder
    }
}
