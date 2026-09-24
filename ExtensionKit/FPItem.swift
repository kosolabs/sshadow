import Common
import FileProvider
import UniformTypeIdentifiers

private let logger = Logger(category: "FPItem")

public class FPItem: NSObject, NSFileProviderItem {
    private let item: Item
    private let packageType: UTType?

    /// A package is created from a template whose content type is a package
    /// type. Reporting the created item as a plain folder is a transition the
    /// system does not support, so it keeps re-issuing the creation; the
    /// created item reports the type it was created from instead.
    public init(item: Item, packageType: UTType? = nil) {
        self.item = item
        self.packageType = packageType
        super.init()
        logger.info("Init \(self.desc)")
    }

    public var itemIdentifier: NSFileProviderItemIdentifier {
        item.id
    }

    public var parentItemIdentifier: NSFileProviderItemIdentifier {
        item.parentId ?? .rootContainer
    }

    public var filename: String { item.name }

    public var contentType: UTType {
        if let packageType {
            return packageType
        }
        return switch item.kind {
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

    public var contentPolicy: NSFileProviderContentPolicy {
        .downloadLazily
    }

    public var fileSystemFlags: NSFileProviderFileSystemFlags {
        NSFileProviderFileSystemFlags(from: item.flags ?? [])
    }

    public var documentSize: NSNumber? {
        item.size as? NSNumber
    }

    public var creationDate: Date? {
        item.createTime ?? item.modifyTime
    }

    public var contentModificationDate: Date? {
        item.modifyTime
    }

    public var lastUsedDate: Date? {
        item.accessTime
    }

    public var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(
            contentVersion: item.contentVersion,
            metadataVersion: item.metadataVersion
        )
    }

    public var symlinkTargetPath: String? {
        if case .symlink(let target) = item.kind { target } else { nil }
    }
}
