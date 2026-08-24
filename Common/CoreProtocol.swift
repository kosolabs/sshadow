import FileProvider
import Foundation

private let logger = Logger(category: "CoreProtocol")

@objc public protocol ExtXPC {
    func attach() async
    func detach() async
}

@objc public protocol CoreXPC {
    func handle(_ data: Data) async throws -> Data
    func handle(
        _ data: Data,
        progressEndpoint: NSXPCListenerEndpoint
    ) async throws -> Data
}

public enum OnExists: Message, PrettyDescribable {
    case fail
    case succeed
}

public enum CoreRequest: Message, PrettyDescribable {
    case name(NameRequest)
    case child(ChildRequest)
    case parent(ParentRequest)
    case item(ItemRequest)
    case list(ListRequest)
    case watch(WatchRequest)
    case unwatch(UnwatchRequest)
    case currentAnchor(CurrentAnchorRequest)
    case changes(ChangesRequest)
    case setAttributes(SetAttributesRequest)
    case createSymlink(CreateSymlinkRequest)
    case createDirectory(CreateDirectoryRequest)
    case move(MoveRequest)
    case removeFile(RemoveFileRequest)
    case removeDirectory(RemoveDirectoryRequest)
    case limits(LimitsRequest)

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> CoreRequest {
        try JSONDecoder().decode(CoreRequest.self, from: data)
    }
}

public enum CoreProgressRequest: Message, PrettyDescribable {
    case upload(UploadRequest)
    case download(DownloadRequest)
    case stream(StreamRequest)

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> CoreProgressRequest {
        try JSONDecoder().decode(CoreProgressRequest.self, from: data)
    }
}

public enum CoreResult: Message, PrettyDescribable {
    case success(CoreResponse)
    case failure(CoreError)

    public func get() throws -> CoreResponse {
        switch self {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> CoreResult {
        try JSONDecoder().decode(CoreResult.self, from: data)
    }
}

public enum CoreResponse: Message, PrettyDescribable {
    case name(NameResponse)
    case child(ChildResponse)
    case parent(ParentResponse)
    case item(ItemResponse)
    case list(ListResponse)
    case watch(WatchResponse)
    case unwatch(UnwatchResponse)
    case currentAnchor(CurrentAnchorResponse)
    case changes(ChangesResponse)
    case setAttributes(SetAttributesResponse)
    case createSymlink(CreateSymlinkResponse)
    case createDirectory(CreateDirectoryResponse)
    case move(MoveResponse)
    case removeFile(RemoveFileResponse)
    case removeDirectory(RemoveDirectoryResponse)
    case limits(LimitsResponse)
    case upload(UploadResponse)
    case download(DownloadResponse)
    case stream(StreamResponse)
}

public enum CoreError: Message, PrettyDescribable, Error {
    case serviceUnreachable
    case profileNotFound
    case userCancelled
    case permissionDenied
    case itemNotFound(String?)
    case filenameCollision
    case serverUnreachable
    case notAuthenticated
    case remotePathNotFound
    case unexpectedResponse
    case unknown(domain: String, code: Int, message: String)

    public static var itemNotFound: CoreError {
        .itemNotFound(nil)
    }

    public static func itemNotFound(
        _ id: NSFileProviderItemIdentifier
    ) -> CoreError {
        .itemNotFound(id.rawValue)
    }

    public init(from error: any Error) {
        if let coreError = error as? CoreError {
            self = coreError
            return
        }
        logger.error("Unhandled error type: \(error)")
        let nsError = error as NSError
        self = .unknown(
            domain: nsError.domain,
            code: nsError.code,
            message: nsError.localizedDescription
        )
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

public struct NameRequest: Message, PrettyDescribable {
    public let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct NameResponse: Message, PrettyDescribable {
    let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct ChildRequest: Message, PrettyDescribable {
    public let parentId: String
    public let name: String

    public init(parentId: String, name: String, ) {
        self.parentId = parentId
        self.name = name
    }
}

public struct ChildResponse: Message, PrettyDescribable {
    let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct ParentRequest: Message, PrettyDescribable {
    public let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct ParentResponse: Message, PrettyDescribable {
    let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct ItemRequest: Message, PrettyDescribable {
    public let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct ItemResponse: Message, PrettyDescribable {
    let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct ListRequest: Message, PrettyDescribable {
    public let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct ListResponse: Message, PrettyDescribable {
    let fileInfos: [Item]

    public init(fileInfos: [Item]) {
        self.fileInfos = fileInfos
    }
}

public struct WatchRequest: Message, PrettyDescribable {
    public let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct WatchResponse: Message, PrettyDescribable {
    public init() {}
}

public struct UnwatchRequest: Message, PrettyDescribable {
    public let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct UnwatchResponse: Message, PrettyDescribable {
    public init() {}
}

public struct CurrentAnchorRequest: Message, PrettyDescribable {
    public init() {}
}

public struct CurrentAnchorResponse: Message, PrettyDescribable {
    public let anchor: UInt64

    public init(anchor: UInt64) {
        self.anchor = anchor
    }
}

public enum Change: Message, PrettyDescribable {
    case delete(itemId: String)
    case update(item: Item)
}

public struct ChangesRequest: Message, PrettyDescribable {
    public let anchor: UInt64

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

public struct SetAttributesRequest: Message, PrettyDescribable {
    public let itemId: String
    public let flags: Item.Flags?
    public let accessTime: Date?
    public let modifyTime: Date?

    public init(
        itemId: String,
        flags: Item.Flags?,
        accessTime: Date?,
        modifyTime: Date?
    ) {
        self.itemId = itemId
        self.flags = flags
        self.accessTime = accessTime
        self.modifyTime = modifyTime
    }
}

public struct SetAttributesResponse: Message, PrettyDescribable {
    public init() {}
}

public struct CreateSymlinkRequest: Message, PrettyDescribable {
    public let parentId: String
    public let name: String
    public let target: String

    public init(
        parentId: String,
        name: String,
        target: String
    ) {
        self.parentId = parentId
        self.name = name
        self.target = target
    }
}

public struct CreateSymlinkResponse: Message, PrettyDescribable {
    let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct CreateDirectoryRequest: Message, PrettyDescribable {
    public let parentId: String
    public let name: String
    public let flags: Item.Flags
    public let ifExists: OnExists

    public init(
        parentId: String,
        name: String,
        flags: Item.Flags,
        ifExists: OnExists
    ) {
        self.parentId = parentId
        self.name = name
        self.flags = flags
        self.ifExists = ifExists
    }
}

public struct CreateDirectoryResponse: Message, PrettyDescribable {
    let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct MoveRequest: Message, PrettyDescribable {
    public let itemId: String
    public let newParentId: String
    public let newName: String

    public init(
        itemId: String,
        newParentId: String,
        newName: String
    ) {
        self.itemId = itemId
        self.newParentId = newParentId
        self.newName = newName
    }
}

public struct MoveResponse: Message, PrettyDescribable {
    public init() {}
}

public struct RemoveFileRequest: Message, PrettyDescribable {
    public let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct RemoveFileResponse: Message, PrettyDescribable {
    public init() {}
}

public struct RemoveDirectoryRequest: Message, PrettyDescribable {
    public let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct RemoveDirectoryResponse: Message, PrettyDescribable {
    public init() {}
}

public struct LimitsRequest: Message, PrettyDescribable {
    public init() {}
}

public struct LimitsResponse: Message, PrettyDescribable {
    public let limits: Limits

    public init(limits: Limits) {
        self.limits = limits
    }
}

public struct UploadRequest: Message, PrettyDescribable {
    public let parentId: String
    public let name: String
    public let file: URL
    public let flags: Item.Flags
    public let chunkSize: UInt64

    public init(
        parentId: String,
        name: String,
        file: URL,
        flags: Item.Flags,
        chunkSize: UInt64
    ) {
        self.parentId = parentId
        self.name = name
        self.file = file
        self.flags = flags
        self.chunkSize = chunkSize
    }
}

public struct UploadResponse: Message, PrettyDescribable {
    let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct DownloadRequest: Message, PrettyDescribable {
    public let itemId: String
    public let chunkSize: UInt64

    public init(itemId: String, chunkSize: UInt64) {
        self.itemId = itemId
        self.chunkSize = chunkSize
    }
}

public struct DownloadResponse: Message, PrettyDescribable {
    let url: URL
    let item: Item

    public init(url: URL, item: Item) {
        self.url = url
        self.item = item
    }
}

public struct StreamRequest: Message, PrettyDescribable {
    public let itemId: String
    public let range: Range<UInt64>

    public init(itemId: String, range: Range<UInt64>) {
        self.itemId = itemId
        self.range = range
    }
}

public struct StreamResponse: Message, PrettyDescribable {
    let url: URL
    let range: Range<UInt64>

    public init(url: URL, range: Range<UInt64>) {
        self.url = url
        self.range = range
    }
}
