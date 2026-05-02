import Common
import FileProvider
import SwiftLibSSH
import UniformTypeIdentifiers

private let logger = Logger(category: "Item")

public class SpecialItem: NSObject, NSFileProviderItem {
    public let itemIdentifier: NSFileProviderItemIdentifier

    init(itemIdentifier: NSFileProviderItemIdentifier) {
        logger.debug("Init \(itemIdentifier.desc)")
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
