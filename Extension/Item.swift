import Common
import FileProvider
import SwiftLibSSH
import UniformTypeIdentifiers

public class Item: NSObject, NSFileProviderItem {
    private let logger: Logger

    public let itemIdentifier: NSFileProviderItemIdentifier
    private let itemAttributes: SFTPAttributes

    init(
        domainName: String,
        itemIdentifier: NSFileProviderItemIdentifier,
        itemAttributes: SFTPAttributes,
    ) {
        logger = Logger(category: "\(domainName):Item")
        logger.debug("Init \(itemIdentifier.desc)")
        self.itemIdentifier = itemIdentifier
        self.itemAttributes = itemAttributes
    }

    public var parentItemIdentifier: NSFileProviderItemIdentifier {
        return itemIdentifier.parent
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
        itemIdentifier.name
    }
    
    public var size: UInt64 {
        itemAttributes.size
    }

    public var documentSize: NSNumber? {
        itemAttributes.size as NSNumber
    }

    public var lastUsedDate: Date? {
        itemAttributes.accessTime
    }

    public var contentModificationDate: Date? {
        itemAttributes.modifyTime
    }

    public var creationDate: Date? {
        itemAttributes.createTime
    }

    public var contentType: UTType {
        itemAttributes.type == .directory ? .folder : .text
    }
}
