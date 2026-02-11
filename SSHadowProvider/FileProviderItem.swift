import FileProvider
import OSLog
import SSHadowShared
import SwiftLibSSH
import UniformTypeIdentifiers


class FileProviderItem: NSObject, NSFileProviderItem {
    private let logger: Logger

    // TODO: implement an initializer to create an item from your extension's backing model
    // TODO: implement the accessors to return the values from your extension's backing model

    let itemIdentifier: NSFileProviderItemIdentifier
    private let itemAttributes: SFTPAttributes

    init(
        domainName: String,
        itemIdentifier: NSFileProviderItemIdentifier,
        itemAttributes: SFTPAttributes,
    ) {
        logger = getLogger(category: "Item.\(domainName)")
        logger.debug("init: \(itemIdentifier.rawValue, privacy: .public)")
        self.itemIdentifier = itemIdentifier
        self.itemAttributes = itemAttributes
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        return itemIdentifier.parent()
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
        itemIdentifier.file
    }
    
    var documentSize: NSNumber? {
        return itemAttributes.size as NSNumber
    }
    
    var lastUsedDate: Date? {
        itemAttributes.accessTime
    }
    
    var contentModificationDate: Date? {
        itemAttributes.modifyTime
    }
    
    var creationDate: Date?{
        itemAttributes.createTime
    }
    
    var contentType: UTType {
        itemAttributes.type == .directory ? .folder : .text
    }
}
