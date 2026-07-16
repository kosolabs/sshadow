import FileProvider
import Foundation

private let logger = Logger(category: "AgentProtocol")

@objc public protocol AppXPC {
    func ping() async throws -> String
}

@objc public protocol ExtXPC {
    func broker() async
}

public enum OnExists: Message, PrettyDescribable {
    case fail
    case succeed
}

public enum AgentRequest: Message, PrettyDescribable {
    public var domainId: UUID {
        switch self {
        case .name(let request):
            request.domainId
        case .child(let request):
            request.domainId
        case .parent(let request):
            request.domainId
        case .item(let request):
            request.domainId
        case .list(let request):
            request.domainId
        case .currentAnchor(let request):
            request.domainId
        case .changes(let request):
            request.domainId
        case .setAttributes(let request):
            request.domainId
        case .createSymlink(let request):
            request.domainId
        case .createDirectory(let request):
            request.domainId
        case .move(let request):
            request.domainId
        case .removeFile(let request):
            request.domainId
        case .removeDirectory(let request):
            request.domainId
        case .limits(let request):
            request.domainId
        case .upload(let request):
            request.domainId
        case .download(let request):
            request.domainId
        case .stream(let request):
            request.domainId
        }
    }

    case name(NameRequest)
    case child(ChildRequest)
    case parent(ParentRequest)
    case item(ItemRequest)
    case list(ListRequest)
    case currentAnchor(CurrentAnchorRequest)
    case changes(ChangesRequest)
    case setAttributes(SetAttributesRequest)
    case createSymlink(CreateSymlinkRequest)
    case createDirectory(CreateDirectoryRequest)
    case move(MoveRequest)
    case removeFile(RemoveFileRequest)
    case removeDirectory(RemoveDirectoryRequest)
    case limits(LimitsRequest)
    case upload(UploadRequest)
    case download(DownloadRequest)
    case stream(StreamRequest)
}

public enum AgentResult: Message, PrettyDescribable {
    case success(AgentResponse)
    case failure(AgentError)

    public func get() throws -> AgentResponse {
        switch self {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }
}

public enum AgentResponse: Message, PrettyDescribable {
    case name(NameResponse)
    case child(ChildResponse)
    case parent(ParentResponse)
    case item(ItemResponse)
    case list(ListResponse)
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

public enum AgentError: Message, PrettyDescribable, Error {
    case agentUnreachable
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

    public static var itemNotFound: AgentError {
        .itemNotFound(nil)
    }

    public static func itemNotFound(
        _ id: NSFileProviderItemIdentifier
    ) -> AgentError {
        .itemNotFound(id.rawValue)
    }

    public init(from error: any Error) {
        if let agentError = error as? AgentError {
            self = agentError
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
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
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
    public let domainId: UUID
    public let parentId: String
    public let name: String

    public init(
        domainId: UUID,
        parentId: String,
        name: String,
    ) {
        self.domainId = domainId
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
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
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
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
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
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct ListResponse: Message, PrettyDescribable {
    let fileInfos: [Item]

    public init(fileInfos: [Item]) {
        self.fileInfos = fileInfos
    }
}

public struct CurrentAnchorRequest: Message, PrettyDescribable {
    public let domainId: UUID

    public init(domainId: UUID) {
        self.domainId = domainId
    }
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
    public let domainId: UUID
    public let anchor: UInt64

    public init(domainId: UUID, anchor: UInt64) {
        self.domainId = domainId
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
    public let domainId: UUID
    public let itemId: String
    public let flags: Item.Flags?
    public let accessTime: Date?
    public let modifyTime: Date?

    public init(
        domainId: UUID,
        itemId: String,
        flags: Item.Flags?,
        accessTime: Date?,
        modifyTime: Date?
    ) {
        self.domainId = domainId
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
    public let domainId: UUID
    public let parentId: String
    public let name: String
    public let target: String

    public init(
        domainId: UUID,
        parentId: String,
        name: String,
        target: String
    ) {
        self.domainId = domainId
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
    public let domainId: UUID
    public let parentId: String
    public let name: String
    public let mode: mode_t
    public let ifExists: OnExists

    public init(
        domainId: UUID,
        parentId: String,
        name: String,
        mode: mode_t,
        ifExists: OnExists
    ) {
        self.domainId = domainId
        self.parentId = parentId
        self.name = name
        self.mode = mode
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
    public let domainId: UUID
    public let itemId: String
    public let newParentId: String
    public let newName: String

    public init(
        domainId: UUID,
        itemId: String,
        newParentId: String,
        newName: String
    ) {
        self.domainId = domainId
        self.itemId = itemId
        self.newParentId = newParentId
        self.newName = newName
    }
}

public struct MoveResponse: Message, PrettyDescribable {
    public init() {}
}

public struct RemoveFileRequest: Message, PrettyDescribable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct RemoveFileResponse: Message, PrettyDescribable {
    public init() {}
}

public struct RemoveDirectoryRequest: Message, PrettyDescribable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct RemoveDirectoryResponse: Message, PrettyDescribable {
    public init() {}
}

public struct LimitsRequest: Message, PrettyDescribable {
    public let domainId: UUID

    public init(domainId: UUID) {
        self.domainId = domainId
    }
}

public struct LimitsResponse: Message, PrettyDescribable {
    public let maxOpenHandles: UInt64
    public let maxPacketLength: UInt64
    public let maxReadLength: UInt64
    public let maxWriteLength: UInt64

    public init(
        maxOpenHandles: UInt64,
        maxPacketLength: UInt64,
        maxReadLength: UInt64,
        maxWriteLength: UInt64
    ) {
        self.maxOpenHandles = maxOpenHandles
        self.maxPacketLength = maxPacketLength
        self.maxReadLength = maxReadLength
        self.maxWriteLength = maxWriteLength
    }
}

public struct UploadRequest: Message, PrettyDescribable {
    public let domainId: UUID
    public let parentId: String
    public let name: String
    public let file: URL
    public let flags: Item.Flags
    public let chunkSize: UInt64
    public let progressEndpoint: XPCEndpoint

    public init(
        domainId: UUID,
        parentId: String,
        name: String,
        file: URL,
        flags: Item.Flags,
        chunkSize: UInt64,
        progressEndpoint: XPCEndpoint
    ) {
        self.domainId = domainId
        self.parentId = parentId
        self.name = name
        self.file = file
        self.flags = flags
        self.chunkSize = chunkSize
        self.progressEndpoint = progressEndpoint
    }
}

public struct UploadResponse: Message, PrettyDescribable {
    let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct DownloadRequest: Message, PrettyDescribable {
    public let domainId: UUID
    public let itemId: String
    public let chunkSize: UInt64
    public let progressEndpoint: XPCEndpoint

    public init(
        domainId: UUID,
        itemId: String,
        chunkSize: UInt64,
        progressEndpoint: XPCEndpoint
    ) {
        self.domainId = domainId
        self.itemId = itemId
        self.chunkSize = chunkSize
        self.progressEndpoint = progressEndpoint
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
    public let domainId: UUID
    public let itemId: String
    public let range: Range<UInt64>
    public let progressEndpoint: XPCEndpoint

    public init(
        domainId: UUID,
        itemId: String,
        range: Range<UInt64>,
        progressEndpoint: XPCEndpoint
    ) {
        self.domainId = domainId
        self.itemId = itemId
        self.range = range
        self.progressEndpoint = progressEndpoint
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
