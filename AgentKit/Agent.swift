import Common
import FileProvider
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "Agent")

public class Agent {
    private let sessions: SessionManager

    public init(appDbStorePath: URL? = nil) {
        self.sessions = SessionManager(appDbStorePath: appDbStorePath)
    }

    public func handle(
        _ request: AgentRequest
    ) async -> AgentResult {
        do {
            logger.debug("Request: \(request)")
            let response: AgentResponse =
                switch request {
                case .name(let request):
                    try await .name(name(request: request))
                case .child(let request):
                    try await .child(child(request: request))
                case .parent(let request):
                    try await .parent(parent(request: request))
                case .pathForItem(let request):
                    try await .path(pathForItem(request: request))
                case .pathForChild(let request):
                    try await .path(pathForChild(request: request))
                case .info(let request):
                    try await .info(info(request: request))
                case .list(let request):
                    try await .list(list(request: request))
                case .exists(let request):
                    try await .exists(exists(request: request))
                case .setAttributes(let request):
                    try await .setAttributes(setAttributes(request: request))
                case .createDirectory(let request):
                    try await .createDirectory(createDirectory(request: request))
                case .move(let request):
                    try await .move(move(request: request))
                case .removeFile(let request):
                    try await .removeFile(removeFile(request: request))
                case .removeDirectory(let request):
                    try await .removeDirectory(removeDirectory(request: request))
                }
            logger.debug("Response: \(response)")
            return .success(response)
        } catch {
            logger.error("Failed to handle request: \(error)")
            return .failure(AgentResultError(from: error))
        }
    }

    func name(
        request: NameRequest
    ) async throws -> NameResponse {
        let session = try await sessions.connect(id: request.domainId)
        let name = try await session.name(
            of: NSFileProviderItemIdentifier(request.itemId)
        )
        return NameResponse(name: name)
    }

    func child(
        request: ChildRequest
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
        request: ParentRequest
    ) async throws -> ParentResponse {
        let session = try await sessions.connect(id: request.domainId)
        let parentId = try await session.parent(
            of: NSFileProviderItemIdentifier(request.itemId)
        )
        return ParentResponse(itemId: parentId.rawValue)
    }

    func pathForItem(
        request: PathForItemRequest
    ) async throws -> PathResponse {
        let session = try await sessions.connect(id: request.domainId)
        let path = await session.path(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return PathResponse(path: path)
    }

    func pathForChild(
        request: PathForChildRequest
    ) async throws -> PathResponse {
        let session = try await sessions.connect(id: request.domainId)
        let path = await session.path(
            for: request.name,
            parentId: NSFileProviderItemIdentifier(request.parentId)
        )
        return PathResponse(path: path)
    }

    func info(
        request: InfoRequest
    ) async throws -> InfoResponse {
        let session = try await sessions.connect(id: request.domainId)
        let info = try await session.info(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return InfoResponse(fileInfo: info)
    }

    func list(
        request: ListRequest
    ) async throws -> ListResponse {
        let session = try await sessions.connect(id: request.domainId)
        let entries = try await session.list(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return ListResponse(fileInfos: entries)
    }

    func exists(
        request: ExistsRequest
    ) async throws -> ExistsResponse {
        let session = try await sessions.connect(id: request.domainId)
        let exists = await session.exists(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return ExistsResponse(exists: exists)
    }

    func setAttributes(
        request: SetAttributesRequest
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

    func createDirectory(
        request: CreateDirectoryRequest
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
        request: MoveRequest
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
        request: RemoveFileRequest
    ) async throws -> RemoveFileResponse {
        let session = try await sessions.connect(id: request.domainId)
        try await session.removeFile(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return RemoveFileResponse()
    }

    func removeDirectory(
        request: RemoveDirectoryRequest
    ) async throws -> RemoveDirectoryResponse {
        let session = try await sessions.connect(id: request.domainId)
        try await session.removeDirectory(
            for: NSFileProviderItemIdentifier(request.itemId)
        )
        return RemoveDirectoryResponse()
    }
}
