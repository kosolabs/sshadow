import FileProvider
import Foundation

private let logger = Logger(category: "AgentProtocol")

public enum OnExists: Codable, PrettyDescribable {
    case fail
    case succeed
}

public enum AgentRequest: Codable, PrettyDescribable {
    public var domainId: UUID {
        switch self {
        case .initDomain(let request):
            request.domainId
        case .deinitDomain(let request):
            request.domainId
        case .name(let request):
            request.domainId
        case .child(let request):
            request.domainId
        case .parent(let request):
            request.domainId
        case .pathForItem(let request):
            request.domainId
        case .pathForChild(let request):
            request.domainId
        case .item(let request):
            request.domainId
        case .list(let request):
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

    case initDomain(InitDomainRequest)
    case deinitDomain(DeinitDomainRequest)
    case name(NameRequest)
    case child(ChildRequest)
    case parent(ParentRequest)
    case pathForItem(PathForItemRequest)
    case pathForChild(PathForChildRequest)
    case item(ItemRequest)
    case list(ListRequest)
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

public enum AgentResult: Codable, PrettyDescribable {
    case success(AgentResponse)
    case failure(AgentError)

    public func get() throws -> AgentResponse {
        switch self {
        case .success(let response): return response
        case .failure(let error): throw error.asError
        }
    }
}

public enum AgentResponse: Codable, PrettyDescribable {
    case initDomain(InitDomainResponse)
    case deinitDomain(DeinitDomainResponse)
    case name(NameResponse)
    case child(ChildResponse)
    case parent(ParentResponse)
    case path(PathResponse)
    case item(ItemResponse)
    case list(ListResponse)
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

public enum AgentError: Codable, PrettyDescribable, Equatable, Error {
    case notAuthenticated
    case serverUnreachable
    case userCancelled
    case permissionDenied
    case itemNotFound(String)
    case filenameCollision
    case unknown(domain: String, code: Int, message: String)

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

    public var asError: any Error {
        switch self {
        case .notAuthenticated:
            NSFileProviderError(.notAuthenticated)
        case .serverUnreachable:
            NSFileProviderError(.serverUnreachable)
        case .userCancelled:
            CocoaError(.userCancelled)
        case .permissionDenied:
            CocoaError(.fileWriteNoPermission)
        case .itemNotFound(let itemId):
            NSError.fileProviderErrorForNonExistentItem(
                withIdentifier: NSFileProviderItemIdentifier(itemId)
            )
        case .filenameCollision:
            NSFileProviderError(.filenameCollision)
        case .unknown(let domain, let code, let message):
            NSError(
                domain: domain,
                code: code,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

public struct InitDomainRequest: Codable, PrettyDescribable {
    public let domainId: UUID

    public init(domainId: UUID) {
        self.domainId = domainId
    }
}

public struct InitDomainResponse: Codable, PrettyDescribable {
    public init() {}
}

public struct DeinitDomainRequest: Codable, PrettyDescribable {
    public let domainId: UUID

    public init(domainId: UUID) {
        self.domainId = domainId
    }
}

public struct DeinitDomainResponse: Codable, PrettyDescribable {
    public init() {}
}

public struct NameRequest: Codable, PrettyDescribable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct NameResponse: Codable, PrettyDescribable {
    let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct ChildRequest: Codable, PrettyDescribable {
    public let domainId: UUID
    public let parentId: String
    public let path: String

    public init(
        domainId: UUID,
        parentId: String,
        path: String,
    ) {
        self.domainId = domainId
        self.parentId = parentId
        self.path = path
    }
}

public struct ChildResponse: Codable, PrettyDescribable {
    let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct ParentRequest: Codable, PrettyDescribable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct ParentResponse: Codable, PrettyDescribable {
    let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct PathForItemRequest: Codable, PrettyDescribable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct PathForChildRequest: Codable, PrettyDescribable {
    public let domainId: UUID
    public let name: String
    public let parentId: String

    public init(domainId: UUID, name: String, parentId: String) {
        self.domainId = domainId
        self.name = name
        self.parentId = parentId
    }
}

public struct PathResponse: Codable, PrettyDescribable {
    let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct ItemRequest: Codable, PrettyDescribable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct ItemResponse: Codable, PrettyDescribable {
    let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct ListRequest: Codable, PrettyDescribable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct ListResponse: Codable, PrettyDescribable {
    let fileInfos: [Item]

    public init(fileInfos: [Item]) {
        self.fileInfos = fileInfos
    }
}

public struct SetAttributesRequest: Codable, PrettyDescribable {
    public let domainId: UUID
    public let itemId: String
    public let permissions: mode_t?
    public let accessTime: Date?
    public let modifyTime: Date?

    public init(
        domainId: UUID,
        itemId: String,
        permissions: mode_t?,
        accessTime: Date?,
        modifyTime: Date?
    ) {
        self.domainId = domainId
        self.itemId = itemId
        self.permissions = permissions
        self.accessTime = accessTime
        self.modifyTime = modifyTime
    }
}

public struct SetAttributesResponse: Codable, PrettyDescribable {
    public init() {}
}

public struct CreateSymlinkRequest: Codable, PrettyDescribable {
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

public struct CreateSymlinkResponse: Codable, PrettyDescribable {
    let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct CreateDirectoryRequest: Codable, PrettyDescribable {
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

public struct CreateDirectoryResponse: Codable, PrettyDescribable {
    let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct MoveRequest: Codable, PrettyDescribable {
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

public struct MoveResponse: Codable, PrettyDescribable {
    public init() {}
}

public struct RemoveFileRequest: Codable, PrettyDescribable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct RemoveFileResponse: Codable, PrettyDescribable {
    public init() {}
}

public struct RemoveDirectoryRequest: Codable, PrettyDescribable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct RemoveDirectoryResponse: Codable, PrettyDescribable {
    public init() {}
}

public struct LimitsRequest: Codable, PrettyDescribable {
    public let domainId: UUID

    public init(domainId: UUID) {
        self.domainId = domainId
    }
}

public struct LimitsResponse: Codable, PrettyDescribable {
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

public struct UploadRequest: Codable, PrettyDescribable {
    public let domainId: UUID
    public let parentId: String
    public let name: String
    public let file: URL
    public let mode: mode_t
    public let chunkSize: UInt64
    public let progressEndpoint: XPCEndpoint

    public init(
        domainId: UUID,
        parentId: String,
        name: String,
        file: URL,
        mode: mode_t,
        chunkSize: UInt64,
        progressEndpoint: XPCEndpoint
    ) {
        self.domainId = domainId
        self.parentId = parentId
        self.name = name
        self.file = file
        self.mode = mode
        self.chunkSize = chunkSize
        self.progressEndpoint = progressEndpoint
    }
}

public struct UploadResponse: Codable, PrettyDescribable {
    let item: Item

    public init(item: Item) {
        self.item = item
    }
}

public struct DownloadRequest: Codable, PrettyDescribable {
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

public struct DownloadResponse: Codable, PrettyDescribable {
    let url: URL
    let item: Item

    public init(url: URL, item: Item) {
        self.url = url
        self.item = item
    }
}

public struct StreamRequest: Codable, PrettyDescribable {
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

public struct StreamResponse: Codable, PrettyDescribable {
    let url: URL
    let range: Range<UInt64>

    public init(url: URL, range: Range<UInt64>) {
        self.url = url
        self.range = range
    }
}
