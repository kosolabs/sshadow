import Common
import FileProvider
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "Agent")

public class Agent: NSObject, AgentProtocol {
    private let sessions: SessionManager

    public init(appDbStorePath: URL? = nil) {
        self.sessions = SessionManager(appDbStorePath: appDbStorePath)
    }

    public func perform(
        _ requestData: Data,
        reply: @escaping (Data) -> Void
    ) {
        Task {
            do {
                let request = try AgentCoding.decode(
                    AgentRequest.self,
                    from: requestData
                )
                logger.debug("Perform: \(request)")
                let response: AgentResponse =
                    switch request {

                    case .name(
                        let domainId,
                        let itemId
                    ):
                        try await name(
                            domainId: domainId,
                            itemId: itemId
                        )

                    case .child(
                        let domainId,
                        let parentId,
                        let path,
                        let ifNotExists
                    ):
                        try await child(
                            domainId: domainId,
                            parentId: parentId,
                            path: path,
                            ifNotExists: ifNotExists
                        )

                    case .parent(
                        let domainId,
                        let itemId
                    ):
                        try await parent(
                            domainId: domainId,
                            itemId: itemId
                        )

                    case .pathForItem(
                        let domainId,
                        let itemId
                    ):
                        try await pathForItem(
                            domainId: domainId,
                            itemId: itemId
                        )

                    case .pathForChild(
                        let domainId,
                        let name,
                        let parentId
                    ):
                        try await pathForChild(
                            domainId: domainId,
                            name: name,
                            parentId: parentId
                        )

                    case .attributes(
                        let domainId,
                        let itemId
                    ):
                        try await attributes(
                            domainId: domainId,
                            itemId: itemId
                        )
                    
                    case .setAttributes(
                        let domainId,
                        let itemId,
                        let permissions,
                        let accessTime,
                        let modifyTime
                    ):
                        try await setAttributes(
                            domainId: domainId,
                            itemId: itemId,
                            permissions: permissions,
                            accessTime: accessTime,
                            modifyTime: modifyTime
                        )
                    
                    case .createDirectory(
                        let domainId,
                        let itemId,
                        let mode,
                        let ifExists
                    ):
                        try await createDirectory(
                            domainId: domainId,
                            itemId: itemId,
                            mode: mode,
                            ifExists: ifExists
                        )

                    case .move(
                        let domainId,
                        let itemId,
                        let newParentId,
                        let newName,
                        let ifParentNotExists
                    ):
                        try await move(
                            domainId: domainId,
                            itemId: itemId,
                            newParentId: newParentId,
                            newName: newName,
                            ifParentNotExists: ifParentNotExists
                        )
                    }
                reply(try AgentCoding.encode(AgentResult.success(response)))
            } catch {
                let result = AgentResult.failure(AgentResultError(from: error))
                reply(try AgentCoding.encode(result))
            }
        }
    }

    func name(
        domainId: UUID,
        itemId: String
    ) async throws -> AgentResponse {
        let session = try await sessions.connect(id: domainId)
        let name = try await session.name(
            of: NSFileProviderItemIdentifier(itemId)
        )
        return .name(name: name)
    }

    func child(
        domainId: UUID,
        parentId: String,
        path: String,
        ifNotExists: DomainDB.OnNotExists
    ) async throws -> AgentResponse {
        let session = try await sessions.connect(id: domainId)
        let childId = try await session.child(
            of: NSFileProviderItemIdentifier(parentId),
            path: path,
            ifNotExists: ifNotExists
        )
        return .child(itemId: childId.rawValue)
    }

    func parent(
        domainId: UUID,
        itemId: String
    ) async throws -> AgentResponse {
        let session = try await sessions.connect(id: domainId)
        let parentId = try await session.parent(
            of: NSFileProviderItemIdentifier(itemId)
        )
        return .parent(itemId: parentId.rawValue)
    }

    func pathForItem(
        domainId: UUID,
        itemId: String
    ) async throws -> AgentResponse {
        let session = try await sessions.connect(id: domainId)
        let path = await session.path(
            for: NSFileProviderItemIdentifier(itemId)
        )
        return .path(path: path)
    }

    func pathForChild(
        domainId: UUID,
        name: String,
        parentId: String
    ) async throws -> AgentResponse {
        let session = try await sessions.connect(id: domainId)
        let path = await session.path(
            for: name,
            parentId: NSFileProviderItemIdentifier(parentId)
        )
        return .path(path: path)
    }

    func attributes(
        domainId: UUID,
        itemId: String
    ) async throws -> AgentResponse {
        let session = try await sessions.connect(id: domainId)
        let attributes = try await session.attributes(
            for: NSFileProviderItemIdentifier(itemId)
        )
        return .attributes(attributes)
    }

    func setAttributes(
        domainId: UUID,
        itemId: String,
        permissions: mode_t?,
        accessTime: Date?,
        modifyTime: Date?
    ) async throws -> AgentResponse {
        let session = try await sessions.connect(id: domainId)
        try await session.setAttributes(
            for: NSFileProviderItemIdentifier(itemId),
            permissions: permissions,
            accessTime: accessTime,
            modifyTime: modifyTime
        )
        return .setAttributes
    }

    func createDirectory(
        domainId: UUID,
        itemId: String,
        mode: mode_t,
        ifExists: OnExists
    ) async throws -> AgentResponse {
        let session = try await sessions.connect(id: domainId)
        try await session.createDirectory(
            for: NSFileProviderItemIdentifier(itemId),
            mode: mode,
            ifExists: ifExists
        )
        return .createDirectory
    }

    func move(
        domainId: UUID,
        itemId: String,
        newParentId: String,
        newName: String,
        ifParentNotExists: OnParentNotExists
    ) async throws -> AgentResponse {
        let session = try await sessions.connect(id: domainId)
        try await session.move(
            NSFileProviderItemIdentifier(itemId),
            toParent: NSFileProviderItemIdentifier(newParentId),
            name: newName,
            ifParentNotExists: ifParentNotExists
        )
        return .move
    }
}
