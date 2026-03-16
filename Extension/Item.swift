import Common
import FileProvider
import SwiftLibSSH
import UniformTypeIdentifiers

public class Item: NSObject, NSFileProviderItem {
    private let logger: Logger

    public let itemIdentifier: NSFileProviderItemIdentifier
    private let itemAttributes: SFTPAttributes
    
    public let parentItemIdentifier: NSFileProviderItemIdentifier
    public let filename: String

    init(
        domainName: String,
        itemIdentifier: NSFileProviderItemIdentifier,
        itemAttributes: SFTPAttributes,
        itemManager: ItemManager
    ) async {
        logger = Logger(category: "\(domainName):Item")
        logger.debug("Init \(itemIdentifier.desc)")
        self.itemIdentifier = itemIdentifier
        self.itemAttributes = itemAttributes
        self.parentItemIdentifier = await itemManager.parent(for: itemIdentifier)
        self.filename = await itemManager.name(for: itemIdentifier)
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
