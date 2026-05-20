import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "Agent")

public class Agent {
    private let sessions: SessionManager
    private let domainDbConfig: ModelConfiguration?

    public init(
        appDb: AppDB,
        domainDbConfig: ModelConfiguration? = nil,
        sharedUrl: URL = SSHadow.groupUrl
    ) {
        self.domainDbConfig = domainDbConfig
        self.sessions = SessionManager(
            appDb: appDb,
            domainDbConfig: domainDbConfig,
            sharedUrl: sharedUrl
        )
    }

    public static func create(
        service: String = SSHadow.appServiceName,
        appDb: AppDB? = nil,
        domainDbConfig: ModelConfiguration? = nil,
        sharedUrl: URL = SSHadow.groupUrl
    ) throws -> XPCListener {
        let db = try appDb ?? AppDB.open()
        return try XPCListener(service: service) { request in
            accept(
                request: request,
                appDb: db,
                domainDbConfig: domainDbConfig,
                sharedUrl: sharedUrl
            )
        }
    }

    public static func createAnonymous(
        appDb: AppDB? = nil,
        domainDbConfig: ModelConfiguration? = nil,
        sharedUrl: URL = SSHadow.groupUrl
    ) -> XPCListener {
        let db = try! appDb ?? AppDB.open()
        return XPCListener(targetQueue: nil) { request in
            accept(
                request: request,
                appDb: db,
                domainDbConfig: domainDbConfig,
                sharedUrl: sharedUrl
            )
        }
    }

    private static func accept(
        request: XPCListener.IncomingSessionRequest,
        appDb: AppDB,
        domainDbConfig: ModelConfiguration?,
        sharedUrl: URL
    ) -> XPCListener.IncomingSessionRequest.Decision {
        let agent = Agent(
            appDb: appDb,
            domainDbConfig: domainDbConfig,
            sharedUrl: sharedUrl
        )
        return request.accept { message in
            let agentRequest: AgentRequest
            do {
                agentRequest = try message.decode(as: AgentRequest.self)
            } catch {
                logger.error("Failed to decode request: \(error)")
                return AgentResult.failure(AgentError(from: error))
            }
            Task {
                logger.debug("Request: \(agentRequest)")
                let agentResult = await agent.handle(agentRequest)
                logger.debug("Result: \(agentResult)")
                message.reply(agentResult)
            }
            return nil
        }
    }

    public func handle(_ request: AgentRequest) async -> AgentResult {
        do {
            let response: AgentResponse =
                switch request {
                case .initDomain(let request):
                    try await .initDomain(initDomain(request))
                case .deinitDomain(let request):
                    try await .deinitDomain(deinitDomain(request))
                case .name(let request):
                    try await .name(name(request))
                case .child(let request):
                    try await .child(child(request))
                case .parent(let request):
                    try await .parent(parent(request))
                case .pathForItem(let request):
                    try await .path(pathForItem(request))
                case .pathForChild(let request):
                    try await .path(pathForChild(request))
                case .item(let request):
                    try await .item(item(request))
                case .list(let request):
                    try await .list(list(request))
                case .exists(let request):
                    try await .exists(exists(request))
                case .setAttributes(let request):
                    try await .setAttributes(setAttributes(request))
                case .createSymlink(let request):
                    try await .createSymlink(createSymlink(request))
                case .createDirectory(let request):
                    try await .createDirectory(createDirectory(request))
                case .move(let request):
                    try await .move(move(request))
                case .removeFile(let request):
                    try await .removeFile(removeFile(request))
                case .removeDirectory(let request):
                    try await .removeDirectory(removeDirectory(request))
                case .limits(let request):
                    try await .limits(limits(request))
                case .upload(let request):
                    try await .upload(upload(request))
                case .download(let request):
                    try await .download(download(request))
                case .stream(let request):
                    try await .stream(stream(request))
                }
            return .success(response)
        } catch SSHError.connectionFailed {
            await sessions.disconnect(id: request.domainId)
            return .failure(.serverUnreachable)
        } catch SSHError.authenticationFailed(_) {
            return .failure(.notAuthenticated)
        } catch {
            return .failure(AgentError(from: error))
        }
    }

    func initDomain(
        _ request: InitDomainRequest
    ) async throws -> InitDomainResponse {
        let domainDbConfig =
            self.domainDbConfig ?? DomainDB.model(for: request.domainId)
        try await DomainDB.open(config: domainDbConfig)
        return InitDomainResponse()
    }

    func deinitDomain(
        _ request: DeinitDomainRequest
    ) async throws -> DeinitDomainResponse {
        try await DomainDB.delete(id: request.domainId)
        return DeinitDomainResponse()
    }

    func name(
        _ request: NameRequest
    ) async throws -> NameResponse {
        let session = try await sessions.connect(id: request.domainId)
        let name = try await session.name(
            of: NSFileProviderItemIdentifier(request.itemId)
        )
        return NameResponse(name: name)
    }

    func child(
        _ request: ChildRequest
    ) async throws -> ChildResponse {
        let session = try await sessions.connect(id: request.domainId)
        let childId = try await session.child(
            of: NSFileProviderItemIdentifier(request.parentId),
            path: request.path,
            ifNotExists: request.ifNotExists
        )
        return ChildResponse(itemId: childId.rawValue)
    }

    func parent(
        _ request: ParentRequest
    ) async throws -> ParentResponse {
        let session = try await sessions.connect(id: request.domainId)
        let parentId = try await session.parent(
            of: NSFileProviderItemIdentifier(request.itemId)
        )
        return ParentResponse(itemId: parentId.rawValue)
    }

    func pathForItem(
        _ request: PathForItemRequest
    ) async throws -> PathResponse {
        let session = try await sessions.connect(id: request.domainId)
        let path = await session.path(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return PathResponse(path: path)
    }

    func pathForChild(
        _ request: PathForChildRequest
    ) async throws -> PathResponse {
        let session = try await sessions.connect(id: request.domainId)
        let path = await session.path(
            for: request.name,
            parentId: NSFileProviderItemIdentifier(request.parentId)
        )
        return PathResponse(path: path)
    }

    func item(
        _ request: ItemRequest
    ) async throws -> ItemResponse {
        let session = try await sessions.connect(id: request.domainId)
        let item = try await session.item(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return ItemResponse(item: item)
    }

    func list(
        _ request: ListRequest
    ) async throws -> ListResponse {
        let session = try await sessions.connect(id: request.domainId)
        let entries = try await session.list(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return ListResponse(fileInfos: entries)
    }

    func exists(
        _ request: ExistsRequest
    ) async throws -> ExistsResponse {
        let session = try await sessions.connect(id: request.domainId)
        let exists = await session.exists(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return ExistsResponse(exists: exists)
    }

    func setAttributes(
        _ request: SetAttributesRequest
    ) async throws -> SetAttributesResponse {
        let session = try await sessions.connect(id: request.domainId)
        try await session.setAttributes(
            for: NSFileProviderItemIdentifier(request.itemId),
            permissions: request.permissions,
            accessTime: request.accessTime,
            modifyTime: request.modifyTime
        )
        return SetAttributesResponse()
    }

    func createSymlink(
        _ request: CreateSymlinkRequest
    ) async throws -> CreateSymlinkResponse {
        let session = try await sessions.connect(id: request.domainId)
        try await session.createSymlink(
            at: NSFileProviderItemIdentifier(request.itemId),
            to: request.target
        )
        return CreateSymlinkResponse()
    }

    func createDirectory(
        _ request: CreateDirectoryRequest
    ) async throws -> CreateDirectoryResponse {
        let session = try await sessions.connect(id: request.domainId)
        try await session.createDirectory(
            for: NSFileProviderItemIdentifier(request.itemId),
            mode: request.mode,
            ifExists: request.ifExists
        )
        return CreateDirectoryResponse()
    }

    func move(
        _ request: MoveRequest
    ) async throws -> MoveResponse {
        let session = try await sessions.connect(id: request.domainId)
        try await session.move(
            NSFileProviderItemIdentifier(request.itemId),
            toParent: NSFileProviderItemIdentifier(request.newParentId),
            name: request.newName,
            ifParentNotExists: request.ifParentNotExists
        )
        return MoveResponse()
    }

    func removeFile(
        _ request: RemoveFileRequest
    ) async throws -> RemoveFileResponse {
        let session = try await sessions.connect(id: request.domainId)
        try await session.removeFile(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return RemoveFileResponse()
    }

    func removeDirectory(
        _ request: RemoveDirectoryRequest
    ) async throws -> RemoveDirectoryResponse {
        let session = try await sessions.connect(id: request.domainId)
        try await session.removeDirectory(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return RemoveDirectoryResponse()
    }

    func limits(
        _ request: LimitsRequest
    ) async throws -> LimitsResponse {
        let session = try await sessions.connect(id: request.domainId)
        let limits = session.limits
        return LimitsResponse(
            maxOpenHandles: limits.maxOpenHandles,
            maxPacketLength: limits.maxPacketLength,
            maxReadLength: limits.maxReadLength,
            maxWriteLength: limits.maxWriteLength
        )
    }

    func upload(
        _ request: UploadRequest
    ) async throws -> UploadResponse {
        let session = try await sessions.connect(id: request.domainId)

        let sync = XPCProgressPublisher(
            endpoint: request.progressEndpoint
        )
        try await session.upload(
            itemId: NSFileProviderItemIdentifier(request.itemId),
            file: request.file,
            mode: request.mode,
            progress: sync.progress
        )
        return UploadResponse()
    }

    func download(
        _ request: DownloadRequest
    ) async throws -> DownloadResponse {
        let session = try await sessions.connect(id: request.domainId)

        let sync = XPCProgressPublisher(
            endpoint: request.progressEndpoint
        )
        let (url, item) = try await session.download(
            itemId: NSFileProviderItemIdentifier(request.itemId),
            progress: sync.progress
        )
        return DownloadResponse(url: url, item: item)
    }

    func stream(
        _ request: StreamRequest
    ) async throws -> StreamResponse {
        let session = try await sessions.connect(id: request.domainId)

        let sync = XPCProgressPublisher(
            endpoint: request.progressEndpoint
        )
        let (url, range) = try await session.stream(
            itemId: NSFileProviderItemIdentifier(request.itemId),
            range: request.range,
            progress: sync.progress
        )
        return StreamResponse(url: url, range: range)
    }
}
