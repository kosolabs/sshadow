import Foundation

public protocol CoreRequestType: Message {
    associatedtype Response: Message
    var wrapped: CoreRequest { get }
}

public struct CurrentAnchorRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = CurrentAnchorResponse
    public var wrapped: CoreRequest { .currentAnchor(self) }

    public init() {}
}

public struct CurrentAnchorResponse: Message, PrettyDescribable {
    public let anchor: UInt64

    public init(anchor: UInt64) {
        self.anchor = anchor
    }
}

public struct LimitsRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = LimitsResponse
    public var wrapped: CoreRequest { .limits(self) }

    public init() {}
}

public struct LimitsResponse: Message, PrettyDescribable {
    public let limits: Limits

    public init(limits: Limits) {
        self.limits = limits
    }
}

public struct IgnoreFilenamesRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = IgnoreFilenamesResponse
    public var wrapped: CoreRequest { .ignoreFilenames(self) }

    public init() {}
}

public struct IgnoreFilenamesResponse: Message, PrettyDescribable {
    public let filenames: [String]

    public init(filenames: [String]) {
        self.filenames = filenames
    }
}

public struct NameRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = NameResponse
    public let itemId: String

    public var wrapped: CoreRequest { .name(self) }

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct NameResponse: Message, PrettyDescribable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct ChildRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = ChildResponse
    public let parentId: String
    public let name: String

    public var wrapped: CoreRequest { .child(self) }

    public init(parentId: String, name: String) {
        self.parentId = parentId
        self.name = name
    }
}

public struct ChildResponse: Message, PrettyDescribable {
    public let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct ParentRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = ParentResponse
    public let itemId: String

    public var wrapped: CoreRequest { .parent(self) }

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct ParentResponse: Message, PrettyDescribable {
    public let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct ItemRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = ItemResponse
    public let itemId: String

    public var wrapped: CoreRequest { .item(self) }

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct ItemResponse: Message, PrettyDescribable {
    public let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct ListRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = ListResponse
    public let itemId: String

    public var wrapped: CoreRequest { .list(self) }

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct ListResponse: Message, PrettyDescribable {
    public let fileInfos: [Item]

    public init(fileInfos: [Item]) {
        self.fileInfos = fileInfos
    }
}

public struct SetWatchedRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = SetWatchedResponse
    public let itemIds: [String]

    public var wrapped: CoreRequest { .setWatched(self) }

    public init(itemIds: [String]) {
        self.itemIds = itemIds
    }
}

public struct SetWatchedResponse: Message, PrettyDescribable {
    public init() {}
}

public struct ChangesRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = ChangesResponse
    public let anchor: UInt64

    public var wrapped: CoreRequest { .changes(self) }

    public init(anchor: UInt64) {
        self.anchor = anchor
    }
}

public struct ChangesResponse: Message, PrettyDescribable {
    public let anchor: UInt64
    public let changes: [Change]

    public init(anchor: UInt64, changes: [Change]) {
        self.anchor = anchor
        self.changes = changes
    }
}

public struct MaterializedItemsChangedRequest: CoreRequestType,
    PrettyDescribable
{
    public typealias Response = MaterializedItemsChangedResponse
    public var wrapped: CoreRequest { .materializedItemsChanged(self) }

    public init() {}
}

public struct MaterializedItemsChangedResponse: Message, PrettyDescribable {
    public init() {}
}

public enum Change: Message, PrettyDescribable {
    case delete(itemId: String)
    case update(item: Item)
}

public struct SetAttributesRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = SetAttributesResponse
    public let itemId: String
    public let flags: Item.Flags?
    public let accessTime: Date?
    public let modifyTime: Date?
    public let snapshot: IgnoreSnapshot?

    public var wrapped: CoreRequest { .setAttributes(self) }

    public init(
        itemId: String,
        flags: Item.Flags?,
        accessTime: Date?,
        modifyTime: Date?,
        snapshot: IgnoreSnapshot?
    ) {
        self.itemId = itemId
        self.flags = flags
        self.accessTime = accessTime
        self.modifyTime = modifyTime
        self.snapshot = snapshot
    }
}

public struct SetAttributesResponse: Message, PrettyDescribable {
    public let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct CreateSymlinkRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = CreateSymlinkResponse
    public let parentId: String
    public let name: String
    public let target: String
    public let snapshot: IgnoreSnapshot?

    public var wrapped: CoreRequest { .createSymlink(self) }

    public init(
        parentId: String,
        name: String,
        target: String,
        snapshot: IgnoreSnapshot?
    ) {
        self.parentId = parentId
        self.name = name
        self.target = target
        self.snapshot = snapshot
    }
}

public struct CreateSymlinkResponse: Message, PrettyDescribable {
    public let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct CreateDirectoryRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = CreateDirectoryResponse
    public let parentId: String
    public let name: String
    public let flags: Item.Flags
    public let snapshot: IgnoreSnapshot?

    public var wrapped: CoreRequest { .createDirectory(self) }

    public init(
        parentId: String,
        name: String,
        flags: Item.Flags,
        snapshot: IgnoreSnapshot?
    ) {
        self.parentId = parentId
        self.name = name
        self.flags = flags
        self.snapshot = snapshot
    }
}

public struct CreateDirectoryResponse: Message, PrettyDescribable {
    public let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct MoveRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = MoveResponse
    public let itemId: String
    public let newParentId: String
    public let newName: String
    public let snapshot: IgnoreSnapshot?

    public var wrapped: CoreRequest { .move(self) }

    public init(
        itemId: String,
        newParentId: String,
        newName: String,
        snapshot: IgnoreSnapshot?
    ) {
        self.itemId = itemId
        self.newParentId = newParentId
        self.newName = newName
        self.snapshot = snapshot
    }
}

public struct MoveResponse: Message, PrettyDescribable {
    public let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct RemoveFileRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = RemoveFileResponse
    public let itemId: String
    public let snapshot: IgnoreSnapshot?

    public var wrapped: CoreRequest { .removeFile(self) }

    public init(itemId: String, snapshot: IgnoreSnapshot?) {
        self.itemId = itemId
        self.snapshot = snapshot
    }
}

public struct RemoveFileResponse: Message, PrettyDescribable {
    public init() {}
}

public struct RemoveDirectoryRequest: CoreRequestType, PrettyDescribable {
    public typealias Response = RemoveDirectoryResponse
    public let itemId: String
    public let snapshot: IgnoreSnapshot?

    public var wrapped: CoreRequest { .removeDirectory(self) }

    public init(itemId: String, snapshot: IgnoreSnapshot?) {
        self.itemId = itemId
        self.snapshot = snapshot
    }
}

public struct RemoveDirectoryResponse: Message, PrettyDescribable {
    public init() {}
}

public protocol CoreProgressRequestType: Message {
    associatedtype Response: Message
    var wrapped: CoreProgressRequest { get }
}

public struct UploadRequest: CoreProgressRequestType, PrettyDescribable {
    public typealias Response = UploadResponse
    public let parentId: String
    public let name: String
    public let file: URL
    public let ifExists: OnExists
    public let chunkSize: UInt64
    public let snapshot: IgnoreSnapshot?

    public var wrapped: CoreProgressRequest { .upload(self) }

    public init(
        parentId: String,
        name: String,
        file: URL,
        ifExists: OnExists,
        chunkSize: UInt64,
        snapshot: IgnoreSnapshot?
    ) {
        self.parentId = parentId
        self.name = name
        self.file = file
        self.ifExists = ifExists
        self.chunkSize = chunkSize
        self.snapshot = snapshot
    }
}

public struct UploadResponse: Message, PrettyDescribable {
    public let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public enum OnExists: Message, PrettyDescribable {
    case fail
    case replace
}

public struct DownloadRequest: CoreProgressRequestType, PrettyDescribable {
    public typealias Response = DownloadResponse
    public let itemId: String
    public let chunkSize: UInt64

    public var wrapped: CoreProgressRequest { .download(self) }

    public init(itemId: String, chunkSize: UInt64) {
        self.itemId = itemId
        self.chunkSize = chunkSize
    }
}

public struct DownloadResponse: Message, PrettyDescribable {
    public let url: URL
    public let item: Item

    public init(url: URL, item: Item) {
        self.url = url
        self.item = item
    }
}

public struct StreamRequest: CoreProgressRequestType, PrettyDescribable {
    public typealias Response = StreamResponse
    public let itemId: String
    public let range: Range<UInt64>

    public var wrapped: CoreProgressRequest { .stream(self) }

    public init(itemId: String, range: Range<UInt64>) {
        self.itemId = itemId
        self.range = range
    }
}

public struct StreamResponse: Message, PrettyDescribable {
    public let url: URL
    public let range: Range<UInt64>

    public init(url: URL, range: Range<UInt64>) {
        self.url = url
        self.range = range
    }
}
