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

    public var contentType: UTType {
        switch info.type {
        case .file:
            .text
        case .folder:
            .folder
        case .symlink(_):
            .symbolicLink
        }
    }

    public var capabilities: NSFileProviderItemCapabilities {
        return [
            .allowsReading, .allowsWriting, .allowsRenaming, .allowsReparenting,
            .allowsTrashing, .allowsDeleting,
        ]
    }

    public var fileSystemFlags: NSFileProviderFileSystemFlags {
        NSFileProviderFileSystemFlags(
            mode: mode_t(truncatingIfNeeded: info.permissions)
        )
    }

    public var documentSize: NSNumber? {
        info.size as NSNumber
    }

    public var creationDate: Date? {
        info.createTime
    }

    public var contentModificationDate: Date? {
        info.modifyTime
    }

    public var lastUsedDate: Date? {
        info.accessTime
    }
    
    public var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(
            contentVersion: "a content version".data(using: .utf8)!,
            metadataVersion: "a metadata version".data(using: .utf8)!
        )
    }

    public var symlinkTargetPath: String? {
        switch info.type {
        case .symlink(let target):
            target
        default:
            nil
        }
    }

    public var size: UInt64 {
        info.size
    }
}
