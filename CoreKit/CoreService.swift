import Common
import FileProvider
import Foundation
import SwiftData
import SwiftLibSSH

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
        await mapError {
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
            case .watch(let request):
                try await .watch(watch(request))
            case .unwatch(let request):
                try await .unwatch(unwatch(request))
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
        await mapError {
            switch request {
            case .upload(let request):
                try await .upload(
                    self.upload(request, progressEndpoint: progressEndpoint)
                )
            case .download(let request):
                try await .download(
                    self.download(request, progressEndpoint: progressEndpoint)
                )
            case .stream(let request):
                try await .stream(
                    self.stream(request, progressEndpoint: progressEndpoint)
                )
            }
        }
    }

    private func mapError(
        _ operation: () async throws -> CoreResponse
    ) async -> CoreResult {
        do {
            return .success(try await operation())
        } catch SSHError.connectionFailed {
            return .failure(.serverUnreachable)
        } catch SSHError.authenticationFailed {
            return .failure(.notAuthenticated)
        } catch SSHError.sftpError(.noSuchFile, _) {
            return .failure(.remotePathNotFound)
        } catch {
            return .failure(CoreError(from: error))
        }
    }

    func name(
        _ request: NameRequest
    ) async throws -> NameResponse {
        try await supervisor.withSession { session in
            let name = try await session.name(
                of: NSFileProviderItemIdentifier(request.itemId)
            )
            return NameResponse(name: name)
        }
    }

    func child(
        _ request: ChildRequest
    ) async throws -> ChildResponse {
        try await supervisor.withSession { session in
            let childId = try await session.child(
                of: NSFileProviderItemIdentifier(request.parentId),
                name: request.name
            )
            return ChildResponse(itemId: childId.rawValue)
        }
    }

    func parent(
        _ request: ParentRequest
    ) async throws -> ParentResponse {
        try await supervisor.withSession { session in
            let parentId = try await session.parent(
                of: NSFileProviderItemIdentifier(request.itemId)
            )
            return ParentResponse(itemId: parentId.rawValue)
        }
    }

    func item(
        _ request: ItemRequest
    ) async throws -> ItemResponse {
        try await supervisor.withSession { session in
            let item = try await session.item(
                for: NSFileProviderItemIdentifier(request.itemId)
            )
            return ItemResponse(item: item)
        }
    }

    func list(
        _ request: ListRequest
    ) async throws -> ListResponse {
        try await supervisor.withSession { session in
            let entries = try await session.list(
                for: NSFileProviderItemIdentifier(request.itemId)
            )
            return ListResponse(fileInfos: entries)
        }
    }

    func watch(
        _ request: WatchRequest
    ) async throws -> WatchResponse {
        try await supervisor.withSession { session in
            await session.watch(
                itemId: NSFileProviderItemIdentifier(request.itemId)
            )
            return WatchResponse()
        }
    }

    func unwatch(
        _ request: UnwatchRequest
    ) async throws -> UnwatchResponse {
        try await supervisor.withSession { session in
            await session.unwatch(
                itemId: NSFileProviderItemIdentifier(request.itemId)
            )
            return UnwatchResponse()
        }
    }

    func currentAnchor(
        _ request: CurrentAnchorRequest
    ) async throws -> CurrentAnchorResponse {
        try await supervisor.withSession { session in
            let anchor = await session.currentAnchor
            return CurrentAnchorResponse(anchor: anchor)
        }
    }

    func changes(
        _ request: ChangesRequest
    ) async throws -> ChangesResponse {
        try await supervisor.withSession { session in
            let (anchor, changes) = await session.changes(
                since: request.anchor
            )
            return ChangesResponse(anchor: anchor, changes: changes)
        }
    }

    func setAttributes(
        _ request: SetAttributesRequest
    ) async throws -> SetAttributesResponse {
        try await supervisor.withSession { session in
            try await session.setAttributes(
                for: NSFileProviderItemIdentifier(request.itemId),
                flags: request.flags,
                accessTime: request.accessTime,
                modifyTime: request.modifyTime
            )
            return SetAttributesResponse()
        }
    }

    func createSymlink(
        _ request: CreateSymlinkRequest
    ) async throws -> CreateSymlinkResponse {
        try await supervisor.withSession { session in
            let item = try await session.createSymlink(
                parentId: NSFileProviderItemIdentifier(request.parentId),
                name: request.name,
                target: request.target
            )
            return CreateSymlinkResponse(item: item)
        }
    }

    func createDirectory(
        _ request: CreateDirectoryRequest
    ) async throws -> CreateDirectoryResponse {
        try await supervisor.withSession { session in
            let item = try await session.createDirectory(
                parentId: NSFileProviderItemIdentifier(request.parentId),
                name: request.name,
                mode: request.mode,
                ifExists: request.ifExists
            )
            return CreateDirectoryResponse(item: item)
        }
    }

    func move(
        _ request: MoveRequest
    ) async throws -> MoveResponse {
        try await supervisor.withSession { session in
            try await session.move(
                NSFileProviderItemIdentifier(request.itemId),
                toParent: NSFileProviderItemIdentifier(request.newParentId),
                name: request.newName
            )
            return MoveResponse()
        }
    }

    func removeFile(
        _ request: RemoveFileRequest
    ) async throws -> RemoveFileResponse {
        try await supervisor.withSession { session in
            try await session.removeFile(
                for: NSFileProviderItemIdentifier(request.itemId)
            )
            return RemoveFileResponse()
        }
    }

    func removeDirectory(
        _ request: RemoveDirectoryRequest
    ) async throws -> RemoveDirectoryResponse {
        try await supervisor.withSession { session in
            try await session.removeDirectory(
                for: NSFileProviderItemIdentifier(request.itemId)
            )
            return RemoveDirectoryResponse()
        }
    }

    func limits(
        _ request: LimitsRequest
    ) async throws -> LimitsResponse {
        try await supervisor.withSession { session in
            let limits = await session.limits
            return LimitsResponse(
                maxOpenHandles: limits.maxOpenHandles,
                maxPacketLength: limits.maxPacketLength,
                maxReadLength: limits.maxReadLength,
                maxWriteLength: limits.maxWriteLength
            )
        }
    }

    func upload(
        _ request: UploadRequest,
        progressEndpoint: NSXPCListenerEndpoint
    ) async throws -> UploadResponse {
        try await supervisor.withSession { session in
            let sync = XPCProgressPublisher(endpoint: progressEndpoint)
            let item = try await session.upload(
                parentId: NSFileProviderItemIdentifier(request.parentId),
                name: request.name,
                file: request.file,
                flags: request.flags,
                baseContentVersion: request.baseContentVersion,
                progress: sync.progress
            )
            return UploadResponse(item: item)
        }
    }

    func download(
        _ request: DownloadRequest,
        progressEndpoint: NSXPCListenerEndpoint
    ) async throws -> DownloadResponse {
        try await supervisor.withSession { session in
            let sync = XPCProgressPublisher(endpoint: progressEndpoint)
            let (url, item) = try await session.download(
                itemId: NSFileProviderItemIdentifier(request.itemId),
                progress: sync.progress
            )
            return DownloadResponse(url: url, item: item)
        }
    }

    func stream(
        _ request: StreamRequest,
        progressEndpoint: NSXPCListenerEndpoint
    ) async throws -> StreamResponse {
        try await supervisor.withSession { session in
            let sync = XPCProgressPublisher(endpoint: progressEndpoint)
            let (url, range) = try await session.stream(
                itemId: NSFileProviderItemIdentifier(request.itemId),
                range: request.range,
                progress: sync.progress
            )
            return StreamResponse(url: url, range: range)
        }
    }
}
