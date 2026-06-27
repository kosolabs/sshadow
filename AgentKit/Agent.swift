import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "Agent")

public class Agent {
    private let sessions: SessionManager
    private let domainDbConfig: ModelConfiguration?

    private init(
        appDb: AppDB,
        domainDbConfig: ModelConfiguration?,
        sharedUrl: URL,
        signal: @escaping SignalEnumerator,
        pollInterval: Duration?
    ) {
        self.domainDbConfig = domainDbConfig
        self.sessions = SessionManager(
            appDb: appDb,
            domainDbConfig: domainDbConfig,
            sharedUrl: sharedUrl,
            signal: signal,
            pollInterval: pollInterval
        )
    }

    public static func listener() throws -> XPCListener {
        let agent = Agent(
            appDb: try AppDB.open(),
            domainDbConfig: nil,
            sharedUrl: SSHadow.groupUrl,
            signal: { config in
                try await config.domain.manager.signalEnumerator(
                    for: .workingSet
                )
            },
            pollInterval: .seconds(30)
        )
        return try XPCListener(service: SSHadow.appServiceName) { request in
            accept(request: request, agent: agent)
        }
    }

    public static func testListener(
        appDb: AppDB,
        domainDbConfig: ModelConfiguration,
        sharedUrl: URL
    ) -> XPCListener {
        let agent = Agent(
            appDb: appDb,
            domainDbConfig: domainDbConfig,
            sharedUrl: sharedUrl,
            signal: { _ in },
            pollInterval: nil
        )
        return XPCListener(targetQueue: nil) { request in
            accept(request: request, agent: agent)
        }
    }

    private static func accept(
        request: XPCListener.IncomingSessionRequest,
        agent: Agent
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
                case .item(let request):
                    try await .item(item(request))
                case .list(let request):
                    try await .list(list(request))
                case .poll(let request):
                    try await .poll(poll(request))
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
        } catch SSHError.connectionFailed(let message)
            where message.contains("Failed to resolve hostname")
        {
            await sessions.disconnect(id: request.domainId)
            return .failure(.unknownHost)
        } catch SSHError.connectionFailed(let message)
            where message.contains("Connection refused")
            || message.contains("Socket error")
            || message.contains("Bad file descriptor")
        {
            await sessions.disconnect(id: request.domainId)
            return .failure(.connectionRefused)
        } catch SSHError.connectionFailed(let message)
            where message.contains("Timeout")
        {
            await sessions.disconnect(id: request.domainId)
            return .failure(.connectionTimedOut)
        } catch SSHError.authenticationFailed(let message)
            where message.contains("Failed to import private key")
        {
            return .failure(.invalidPrivateKey)
        } catch SSHError.authenticationFailed {
            return .failure(.passwordAuthFailed)
        } catch SSHError.sftpError(.noSuchFile, _) {
            return .failure(.remotePathNotFound)
        } catch {
            return .failure(AgentError(from: error))
        }
    }

    func initDomain(
        _ request: InitDomainRequest
    ) async throws -> InitDomainResponse {
        let config = request.config
        try await SSHClient.withSession(config: config) { _, sftp in
            let attrs = try await sftp.attributes(at: config.path())
            if attrs.type != .directory {
                throw AgentError.remotePathNotDirectory
            }
        }

        let domainDbConfig =
            self.domainDbConfig ?? DomainDB.model(for: config.id)
        try await DomainDB.open(config: domainDbConfig)
        try await sessions.connect(id: config.id)
        return InitDomainResponse()
    }

    func deinitDomain(
        _ request: DeinitDomainRequest
    ) async throws -> DeinitDomainResponse {
        await sessions.disconnect(id: request.domainId)
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

    func poll(
        _ request: PollRequest
    ) async throws -> PollResponse {
        let session = try await sessions.connect(id: request.domainId)
        try await session.poll()
        return PollResponse()
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
