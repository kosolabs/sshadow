import Common
import FileProvider
import UniformTypeIdentifiers

private let logger = Logger(category: "FPItem")

public class FPItem: NSObject, NSFileProviderItem {
    private let item: Item

    public init(item: Item) {
        self.item = item
        logger.debug("Init FPItemID(\(item.rawId), \(item.name))")
    }

    public var itemIdentifier: NSFileProviderItemIdentifier {
        item.id
    }

    public var parentItemIdentifier: NSFileProviderItemIdentifier {
        item.parentId ?? .rootContainer
    }

    public var filename: String { item.name }

    public var contentType: UTType {
        switch item.kind {
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
            contentVersion: "a content version".data(using: .utf8)!,
            metadataVersion: "a metadata version".data(using: .utf8)!
        )
    }

    public var symlinkTargetPath: String? {
        if case .symlink(let target) = item.kind { target } else { nil }
    }
}
