import FileProvider
import Foundation

private let logger = Logger(category: "AgentProtocol")

public enum OnExists: Codable {
    case fail
    case succeed
}

public enum OnNotExists: Codable {
    case fail
    case create
}

public enum OnParentNotExists: Codable {
    case fail
    case create
}

public enum AgentRequest: Codable {
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
        case .info(let request):
            request.domainId
        case .list(let request):
            request.domainId
        case .exists(let request):
            request.domainId
        case .setAttributes(let request):
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
    case info(InfoRequest)
    case list(ListRequest)
    case exists(ExistsRequest)
    case setAttributes(SetAttributesRequest)
    case createDirectory(CreateDirectoryRequest)
    case move(MoveRequest)
    case removeFile(RemoveFileRequest)
    case removeDirectory(RemoveDirectoryRequest)
    case limits(LimitsRequest)
    case upload(UploadRequest)
    case download(DownloadRequest)
    case stream(StreamRequest)
}

public enum AgentResult: Codable {
    case success(AgentResponse)
    case failure(AgentError)

    public func get() throws -> AgentResponse {
        switch self {
        case .success(let response): return response
        case .failure(let error): throw error.asError
        }
    }
}

public enum AgentResponse: Codable {
    case initDomain(InitDomainResponse)
    case deinitDomain(DeinitDomainResponse)
    case name(NameResponse)
    case child(ChildResponse)
    case parent(ParentResponse)
    case path(PathResponse)
    case info(InfoResponse)
    case list(ListResponse)
    case exists(ExistsResponse)
    case setAttributes(SetAttributesResponse)
    case createDirectory(CreateDirectoryResponse)
    case move(MoveResponse)
    case removeFile(RemoveFileResponse)
    case removeDirectory(RemoveDirectoryResponse)
    case limits(LimitsResponse)
    case upload(UploadResponse)
    case download(DownloadResponse)
    case stream(StreamResponse)
}

public enum AgentError: Codable, Equatable, Error{
    case notAuthenticated
    case serverUnreachable
    case userCancelled
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
        case .userCancelled:
            CocoaError(.userCancelled)
        case .itemNotFound(let itemId):
            NSError.fileProviderErrorForNonExistentItem(
                withIdentifier: NSFileProviderItemIdentifier(itemId)
            )
        case .filenameCollision:
            NSFileProviderError(.filenameCollision)
        case .serverUnreachable:
            NSFileProviderError(.serverUnreachable)
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

public struct InitDomainRequest: Codable {
    public let domainId: UUID

    public init(domainId: UUID) {
        self.domainId = domainId
    }
}

public struct InitDomainResponse: Codable {
    public init() {}
}

public struct DeinitDomainRequest: Codable {
    public let domainId: UUID

    public init(domainId: UUID) {
        self.domainId = domainId
    }
}

public struct DeinitDomainResponse: Codable {
    public init() {}
}

public struct NameRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct NameResponse: Codable {
    let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct ChildRequest: Codable {
    public let domainId: UUID
    public let parentId: String
    public let path: String
    public let ifNotExists: OnNotExists

    public init(
        domainId: UUID,
        parentId: String,
        path: String,
        ifNotExists: OnNotExists
    ) {
        self.domainId = domainId
        self.parentId = parentId
        self.path = path
        self.ifNotExists = ifNotExists
    }
}

public struct ChildResponse: Codable {
    let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct ParentRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct ParentResponse: Codable {
    let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct PathForItemRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct PathForChildRequest: Codable {
    public let domainId: UUID
    public let name: String
    public let parentId: String

    public init(domainId: UUID, name: String, parentId: String) {
        self.domainId = domainId
        self.name = name
        self.parentId = parentId
    }
}

public struct PathResponse: Codable {
    let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct InfoRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct InfoResponse: Codable {
    let fileInfo: FileInfo

    public init(fileInfo: FileInfo) {
        self.fileInfo = fileInfo
    }
}

public struct ListRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct ListResponse: Codable {
    let fileInfos: [FileInfo]

    public init(fileInfos: [FileInfo]) {
        self.fileInfos = fileInfos
    }
}

public struct ExistsRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct ExistsResponse: Codable {
    let exists: Bool

    public init(exists: Bool) {
        self.exists = exists
    }
}

public struct SetAttributesRequest: Codable {
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

public struct SetAttributesResponse: Codable {
    public init() {}
}

public struct CreateDirectoryRequest: Codable {
    public let domainId: UUID
    public let itemId: String
    public let mode: mode_t
    public let ifExists: OnExists

    public init(
        domainId: UUID,
        itemId: String,
        mode: mode_t,
        ifExists: OnExists
    ) {
        self.domainId = domainId
        self.itemId = itemId
        self.mode = mode
        self.ifExists = ifExists
    }
}

public struct CreateDirectoryResponse: Codable {
    public init() {}
}

public struct MoveRequest: Codable {
    public let domainId: UUID
    public let itemId: String
    public let newParentId: String
    public let newName: String
    public let ifParentNotExists: OnParentNotExists

    public init(
        domainId: UUID,
        itemId: String,
        newParentId: String,
        newName: String,
        ifParentNotExists: OnParentNotExists
    ) {
        self.domainId = domainId
        self.itemId = itemId
        self.newParentId = newParentId
        self.newName = newName
        self.ifParentNotExists = ifParentNotExists
    }
}

public struct MoveResponse: Codable {
    public init() {}
}

public struct RemoveFileRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct RemoveFileResponse: Codable {
    public init() {}
}

public struct RemoveDirectoryRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct RemoveDirectoryResponse: Codable {
    public init() {}
}

public struct LimitsRequest: Codable {
    public let domainId: UUID

    public init(domainId: UUID) {
        self.domainId = domainId
    }
}

public struct LimitsResponse: Codable {
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

public struct UploadRequest: Codable {
    public let domainId: UUID
    public let itemId: String
    public let file: URL
    public let mode: mode_t
    public let chunkSize: UInt64
    public let progressEndpoint: XPCEndpoint

    public init(
        domainId: UUID,
        itemId: String,
        file: URL,
        mode: mode_t,
        chunkSize: UInt64,
        progressEndpoint: XPCEndpoint
    ) {
        self.domainId = domainId
        self.itemId = itemId
        self.file = file
        self.mode = mode
        self.chunkSize = chunkSize
        self.progressEndpoint = progressEndpoint
    }
}

public struct UploadResponse: Codable {
    public init() {}
}

public struct DownloadRequest: Codable {
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

public struct DownloadResponse: Codable {
    let url: URL
    let fileInfo: FileInfo

    public init(url: URL, fileInfo: FileInfo) {
        self.url = url
        self.fileInfo = fileInfo
    }
}

public struct StreamRequest: Codable {
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

public struct StreamResponse: Codable {
    let url: URL
    let range: Range<UInt64>

    public init(url: URL, range: Range<UInt64>) {
        self.url = url
        self.range = range
    }
}
