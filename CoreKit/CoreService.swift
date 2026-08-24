import Common
import FileProvider
import Foundation
import SwiftData

private let logger = Logger(category: "CoreService")

final class CoreService: Sendable, CoreXPC {
    private let supervisor: SessionSupervisor

    init(supervisor: SessionSupervisor) {
        self.supervisor = supervisor
    }

    func handle(_ data: Data) async throws -> Data {
        let request: CoreRequest
        do {
            request = try CoreRequest.decoded(from: data)
        } catch {
            logger.error("Failed to decode request: \(error)")
            return try JSONEncoder().encode(
                CoreResult.failure(CoreError(from: error))
            )
        }
        logger.debug("Request: \(request)")
        let result = await handle(request)
        logger.debug("Result: \(result)")
        return try result.encoded()
    }

    func handle(_ request: CoreRequest) async -> CoreResult {
        await respond { session in
            switch request {
            case .name(let request):
                try await .name(name(session, request))
            case .child(let request):
                try await .child(child(session, request))
            case .parent(let request):
                try await .parent(parent(session, request))
            case .item(let request):
                try await .item(item(session, request))
            case .list(let request):
                try await .list(list(session, request))
            case .watch(let request):
                try await .watch(watch(session, request))
            case .unwatch(let request):
                try await .unwatch(unwatch(session, request))
            case .currentAnchor(let request):
                try await .currentAnchor(currentAnchor(session, request))
            case .changes(let request):
                try await .changes(changes(session, request))
            case .setAttributes(let request):
                try await .setAttributes(setAttributes(session, request))
            case .createSymlink(let request):
                try await .createSymlink(createSymlink(session, request))
            case .createDirectory(let request):
                try await .createDirectory(createDirectory(session, request))
            case .move(let request):
                try await .move(move(session, request))
            case .removeFile(let request):
                try await .removeFile(removeFile(session, request))
            case .removeDirectory(let request):
                try await .removeDirectory(removeDirectory(session, request))
            case .limits(let request):
                try await .limits(limits(session, request))
            }
        }
    }

    public func handle(
        _ data: Data,
        progressEndpoint: NSXPCListenerEndpoint
    ) async throws -> Data {
        let request: CoreProgressRequest
        do {
            request = try CoreProgressRequest.decoded(from: data)
        } catch {
            logger.error("Failed to decode request: \(error)")
            return try JSONEncoder().encode(
                CoreResult.failure(CoreError(from: error))
            )
        }
        logger.debug("Request: \(request)")
        let result = await handle(request, progressEndpoint: progressEndpoint)
        logger.debug("Result: \(result)")
        return try result.encoded()
    }

    public func handle(
        _ request: CoreProgressRequest,
        progressEndpoint: NSXPCListenerEndpoint
    ) async -> CoreResult {
        await respond { session in
            switch request {
            case .upload(let request):
                try await .upload(
                    self.upload(
                        session,
                        request,
                        progressEndpoint: progressEndpoint
                    )
                )
            case .download(let request):
                try await .download(
                    self.download(
                        session,
                        request,
                        progressEndpoint: progressEndpoint
                    )
                )
            case .stream(let request):
                try await .stream(
                    self.stream(
                        session,
                        request,
                        progressEndpoint: progressEndpoint
                    )
                )
            }
        }
    }

    private func respond(
        _ operation: @Sendable (Session) async throws -> CoreResponse
    ) async -> CoreResult {
        do {
            return .success(try await supervisor.withSession(operation))
        } catch {
            return .failure(CoreError(from: error))
        }
    }

    func name(
        _ session: Session,
        _ request: NameRequest
    ) async throws -> NameResponse {
        let name = try await session.name(
            of: NSFileProviderItemIdentifier(request.itemId)
        )
        return NameResponse(name: name)
    }

    func child(
        _ session: Session,
        _ request: ChildRequest
    ) async throws -> ChildResponse {
        let childId = try await session.child(
            of: NSFileProviderItemIdentifier(request.parentId),
            name: request.name
        )
        return ChildResponse(itemId: childId.rawValue)
    }

    func parent(
        _ session: Session,
        _ request: ParentRequest
    ) async throws -> ParentResponse {
        let parentId = try await session.parent(
            of: NSFileProviderItemIdentifier(request.itemId)
        )
        return ParentResponse(itemId: parentId.rawValue)
    }

    func item(
        _ session: Session,
        _ request: ItemRequest
    ) async throws -> ItemResponse {
        let item = try await session.item(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return ItemResponse(item: item)
    }

    func list(
        _ session: Session,
        _ request: ListRequest
    ) async throws -> ListResponse {
        let entries = try await session.list(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return ListResponse(fileInfos: entries)
    }

    func watch(
        _ session: Session,
        _ request: WatchRequest
    ) async throws -> WatchResponse {
        await session.watch(
            itemId: NSFileProviderItemIdentifier(request.itemId)
        )
        return WatchResponse()
    }

    func unwatch(
        _ session: Session,
        _ request: UnwatchRequest
    ) async throws -> UnwatchResponse {
        await session.unwatch(
            itemId: NSFileProviderItemIdentifier(request.itemId)
        )
        return UnwatchResponse()
    }

    func currentAnchor(
        _ session: Session,
        _ request: CurrentAnchorRequest
    ) async throws -> CurrentAnchorResponse {
        await CurrentAnchorResponse(anchor: session.anchor)
    }

    func changes(
        _ session: Session,
        _ request: ChangesRequest
    ) async throws -> ChangesResponse {
        let (anchor, changes) = await session.changes(
            since: request.anchor
        )
        return ChangesResponse(anchor: anchor, changes: changes)
    }

    func setAttributes(
        _ session: Session,
        _ request: SetAttributesRequest
    ) async throws -> SetAttributesResponse {
        try await session.setAttributes(
            for: NSFileProviderItemIdentifier(request.itemId),
            flags: request.flags,
            accessTime: request.accessTime,
            modifyTime: request.modifyTime
        )
        return SetAttributesResponse()
    }

    func createSymlink(
        _ session: Session,
        _ request: CreateSymlinkRequest
    ) async throws -> CreateSymlinkResponse {
        let item = try await session.createSymlink(
            request.name,
            in: NSFileProviderItemIdentifier(request.parentId),
            target: request.target
        )
        return CreateSymlinkResponse(item: item)
    }

    func createDirectory(
        _ session: Session,
        _ request: CreateDirectoryRequest
    ) async throws -> CreateDirectoryResponse {
        let item = try await session.createDirectory(
            request.name,
            in: NSFileProviderItemIdentifier(request.parentId),
            flags: request.flags,
            ifExists: request.ifExists
        )
        return CreateDirectoryResponse(item: item)
    }

    func move(
        _ session: Session,
        _ request: MoveRequest
    ) async throws -> MoveResponse {
        try await session.move(
            NSFileProviderItemIdentifier(request.itemId),
            to: NSFileProviderItemIdentifier(request.newParentId),
            name: request.newName
        )
        return MoveResponse()
    }

    func removeFile(
        _ session: Session,
        _ request: RemoveFileRequest
    ) async throws -> RemoveFileResponse {
        try await session.removeFile(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return RemoveFileResponse()
    }

    func removeDirectory(
        _ session: Session,
        _ request: RemoveDirectoryRequest
    ) async throws -> RemoveDirectoryResponse {
        try await session.removeDirectory(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return RemoveDirectoryResponse()
    }

    func limits(
        _ session: Session,
        _ request: LimitsRequest
    ) async throws -> LimitsResponse {
        await LimitsResponse(limits: session.limits)
    }

    func upload(
        _ session: Session,
        _ request: UploadRequest,
        progressEndpoint: NSXPCListenerEndpoint
    ) async throws -> UploadResponse {
        let sync = XPCProgressPublisher(endpoint: progressEndpoint)
        let item = try await session.upload(
            request.name,
            to: NSFileProviderItemIdentifier(request.parentId),
            file: request.file,
            flags: request.flags,
            progress: sync.progress
        )
        return UploadResponse(item: item)
    }

    func download(
        _ session: Session,
        _ request: DownloadRequest,
        progressEndpoint: NSXPCListenerEndpoint
    ) async throws -> DownloadResponse {
        let sync = XPCProgressPublisher(endpoint: progressEndpoint)
        let (url, item) = try await session.download(
            itemId: NSFileProviderItemIdentifier(request.itemId),
            progress: sync.progress
        )
        return DownloadResponse(url: url, item: item)
    }

    func stream(
        _ session: Session,
        _ request: StreamRequest,
        progressEndpoint: NSXPCListenerEndpoint
    ) async throws -> StreamResponse {
        let sync = XPCProgressPublisher(endpoint: progressEndpoint)
        let (url, range) = try await session.stream(
            itemId: NSFileProviderItemIdentifier(request.itemId),
            range: request.range,
            progress: sync.progress
        )
        return StreamResponse(url: url, range: range)
    }
}
