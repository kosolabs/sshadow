import Common
import FileProvider
import UniformTypeIdentifiers

private let logger = Logger(category: "Item")

public class Item: NSObject, NSFileProviderItem {
    private let info: FileInfo

    public init(info: FileInfo) {
        self.info = info
        logger.debug("Init FPItemID(\(info.id), \(info.name))")
    }

    public var itemIdentifier: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(info.id)
    }

    public var parentItemIdentifier: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(info.parentId)
    }

    public var filename: String { info.name }

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

    public var size: UInt64 { info.size }

    public var documentSize: NSNumber? { info.size as NSNumber }

    public var lastUsedDate: Date? { info.accessTime }

    public var contentModificationDate: Date? { info.modifyTime }

    public var creationDate: Date? { info.createTime }

    public var isDirectory: Bool { info.isDirectory }

    public var contentType: UTType {
        info.isDirectory ? .folder : .text
    }
}
