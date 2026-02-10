import FileProvider
import OSLog
import SSHadowShared
import SwiftLibSSH
import UniformTypeIdentifiers

class FileProviderSpecialItem: NSObject, NSFileProviderItem {
    private let logger: Logger
    let itemIdentifier: NSFileProviderItemIdentifier

    init(
        domainName: String,
        itemIdentifier: NSFileProviderItemIdentifier,
    ) {
        logger = getLogger(category: "Item.\(domainName)")
        logger.debug("init: \(itemIdentifier.rawValue, privacy: .public)")
        self.itemIdentifier = itemIdentifier
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        return .rootContainer
    }

    var capabilities: NSFileProviderItemCapabilities {
        return [
            .allowsReading, .allowsWriting, .allowsRenaming, .allowsReparenting,
            .allowsTrashing, .allowsDeleting,
        ]
    }

    var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(
            contentVersion: "a content version".data(using: .utf8)!,
            metadataVersion: "a metadata version".data(using: .utf8)!
        )
    }

    var filename: String {
        return itemIdentifier.rawValue
    }

    var contentType: UTType {
        .folder
    }
}
