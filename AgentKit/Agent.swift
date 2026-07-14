import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "Agent")

public final class Agent: Sendable {
    public static let shared: Agent = Agent(
        appDb: AppDB.shared,
        domainDbConfig: nil,
        sharedUrl: SSHadow.groupUrl,
        signal: { config in
            try await config.domain.manager.signalEnumerator(
                for: .workingSet
            )
        },
        transfers: Transfers(),
        pollInterval: .seconds(30),
    )

    private let sessions: SessionManager
    private let domainDbConfig: ModelConfiguration?

    public init(
        appDb: AppDB,
        domainDbConfig: ModelConfiguration?,
        sharedUrl: URL,
        signal: @escaping SignalEnumerator,
        transfers: Transfers,
        pollInterval: Duration?
    ) {
        self.domainDbConfig = domainDbConfig
        self.sessions = SessionManager(
            appDb: appDb,
            domainDbConfig: domainDbConfig,
            sharedUrl: sharedUrl,
            signal: signal,
            transfers: transfers,
            pollInterval: pollInterval
        )
    }

    public static func testListener(
        appDb: AppDB,
        domainDbConfig: ModelConfiguration,
        sharedUrl: URL,
        transfers: Transfers
    ) -> XPCListener {
        let agent = Agent(
            appDb: appDb,
            domainDbConfig: domainDbConfig,
            sharedUrl: sharedUrl,
            signal: { _ in },
            transfers: transfers,
            pollInterval: nil,
        )
        return XPCListener(targetQueue: nil) { request in
            agent.accept(request: request)
        }
    }

    public func accept(
        request: XPCListener.IncomingSessionRequest,
    ) -> XPCListener.IncomingSessionRequest.Decision {
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
                let agentResult = await self.handle(agentRequest)
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
                case .name(let request):
                    try await .name(name(request))
                case .child(let request):
                    try await .child(child(request))
                case .parent(let request):
                    try await .parent(parent(request))
                case .item(let request):
                    try await .item(item(request))
                case .list(let request):
                    try await .list(list(request))
                case .currentAnchor(let request):
                    try await .currentAnchor(currentAnchor(request))
                case .changes(let request):
                    try await .changes(changes(request))
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
        } catch SSHError.authenticationFailed {
            return .failure(.notAuthenticated)
        } catch SSHError.sftpError(.noSuchFile, _) {
            return .failure(.remotePathNotFound)
        } catch {
            return .failure(AgentError(from: error))
        }
    }
    
    // MARK: App

    func initDomain(_ domainId: UUID) async throws {
        let domainDbConfig =
            self.domainDbConfig ?? DomainDB.model(for: domainId)
        try await DomainDB.open(config: domainDbConfig)
        try await sessions.connect(id: domainId)
    }

    func deinitDomain(_ domainId: UUID) async throws {
        await sessions.disconnect(id: domainId)
        try await DomainDB.delete(id: domainId)
    }
    
    func poll(domainId: UUID) async throws {
        let session = try await sessions.connect(id: domainId)
        try await session.poll()
    }
    
    // MARK: Extension

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
            name: request.name
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

    func currentAnchor(
        _ request: CurrentAnchorRequest
    ) async throws -> CurrentAnchorResponse {
        let session = try await sessions.connect(id: request.domainId)
        let anchor = await session.currentAnchor
        return CurrentAnchorResponse(anchor: anchor)
    }

    func changes(
        _ request: ChangesRequest
    ) async throws -> ChangesResponse {
        let session = try await sessions.connect(id: request.domainId)
        let (anchor, changes) = await session.changes(since: request.anchor)
        return ChangesResponse(anchor: anchor, changes: changes)
    }

    func setAttributes(
        _ request: SetAttributesRequest
    ) async throws -> SetAttributesResponse {
        let session = try await sessions.connect(id: request.domainId)
        try await session.setAttributes(
            for: NSFileProviderItemIdentifier(request.itemId),
            flags: request.flags,
            accessTime: request.accessTime,
            modifyTime: request.modifyTime
        )
        return SetAttributesResponse()
    }

    func createSymlink(
        _ request: CreateSymlinkRequest
    ) async throws -> CreateSymlinkResponse {
        let session = try await sessions.connect(id: request.domainId)
        let item = try await session.createSymlink(
            parentId: NSFileProviderItemIdentifier(request.parentId),
            name: request.name,
            target: request.target
        )
        return CreateSymlinkResponse(item: item)
    }

    func createDirectory(
        _ request: CreateDirectoryRequest
    ) async throws -> CreateDirectoryResponse {
        let session = try await sessions.connect(id: request.domainId)
        let item = try await session.createDirectory(
            parentId: NSFileProviderItemIdentifier(request.parentId),
            name: request.name,
            mode: request.mode,
            ifExists: request.ifExists
        )
        return CreateDirectoryResponse(item: item)
    }

    func move(
        _ request: MoveRequest
    ) async throws -> MoveResponse {
        let session = try await sessions.connect(id: request.domainId)
        try await session.move(
            NSFileProviderItemIdentifier(request.itemId),
            toParent: NSFileProviderItemIdentifier(request.newParentId),
            name: request.newName
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
        let limits = await session.limits
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
        let item = try await session.upload(
            parentId: NSFileProviderItemIdentifier(request.parentId),
            name: request.name,
            file: request.file,
            flags: request.flags,
            progress: sync.progress
        )
        return UploadResponse(item: item)
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
