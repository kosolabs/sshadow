import FileProvider
import Foundation
import SwiftLibSSH
import XPC

private let logger = Logger(category: "AgentClient")

public class AgentClient {
    private let domainId: UUID
    private let session: XPCSession

    public convenience init(domainId: UUID) {
        let session = try! XPCSession(
            machService: SSHadow.appServiceName
        )
        self.init(domainId: domainId, session: session)
    }

    public init(domainId: UUID, session: XPCSession) {
        self.domainId = domainId
        self.session = session
        logger.info("Connected to: \(session)")
    }

    deinit {
        session.cancel(reason: "AgentClient deallocated")
    }

    private func perform(
        _ request: AgentRequest
    ) async throws -> AgentResponse {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.send(request) {
                    (result: Result<AgentResult, any Error>) in
                    do {
                        continuation.resume(
                            returning: try result.get().get()
                        )
                    } catch {
                        logger.error("Request failed: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                logger.error("Failed to send request: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }

    public func name(
        of itemId: NSFileProviderItemIdentifier
    ) async throws -> String {
        let response = try await perform(
            .name(domainId: domainId, itemId: itemId.rawValue)
        )
        guard case .name(let name) = response else {
            throw CocoaError(.coderInvalidValue)
        }
        return name
    }

    public func child(
        of parentId: NSFileProviderItemIdentifier = .rootContainer,
        path: String,
        ifNotExists: DomainDB.OnNotExists = .create
    ) async throws -> NSFileProviderItemIdentifier {
        let response = try await perform(
            .child(
                domainId: domainId,
                parentId: parentId.rawValue,
                path: path,
                ifNotExists: ifNotExists
            )
        )
        guard case .child(let itemId) = response else {
            throw CocoaError(.coderInvalidValue)
        }
        return NSFileProviderItemIdentifier(itemId)
    }

    public func parent(
        of itemId: NSFileProviderItemIdentifier
    ) async throws -> NSFileProviderItemIdentifier {
        let response = try await perform(
            .parent(
                domainId: domainId,
                itemId: itemId.rawValue
            )
        )
        guard case .parent(let parentId) = response else {
            throw CocoaError(.coderInvalidValue)
        }
        return NSFileProviderItemIdentifier(parentId)
    }

    public func path(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> String {
        let response = try await perform(
            .pathForItem(
                domainId: domainId,
                itemId: itemId.rawValue
            )
        )
        guard case .path(let path) = response else {
            throw CocoaError(.coderInvalidValue)
        }
        return path
    }

    public func path(
        for name: String,
        parentId: NSFileProviderItemIdentifier
    ) async throws -> String {
        let response = try await perform(
            .pathForChild(
                domainId: domainId,
                name: name,
                parentId: parentId.rawValue
            )
        )
        guard case .path(let path) = response else {
            throw CocoaError(.coderInvalidValue)
        }
        return path
    }

    public func info(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> FileInfo {
        let response = try await perform(
            .info(domainId: domainId, itemId: itemId.rawValue)
        )
        guard case .info(let info) = response else {
            throw CocoaError(.coderInvalidValue)
        }
        return info
    }

    public func list(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> [FileInfo] {
        let response = try await perform(
            .list(domainId: domainId, itemId: itemId.rawValue)
        )
        guard case .list(let entries) = response else {
            throw CocoaError(.coderInvalidValue)
        }
        return entries
    }

    public func setAttributes(
        for itemId: NSFileProviderItemIdentifier,
        permissions: mode_t? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil
    ) async throws {
        let response = try await perform(
            .setAttributes(
                domainId: domainId,
                itemId: itemId.rawValue,
                permissions: permissions,
                accessTime: accessTime,
                modifyTime: modifyTime
            )
        )
        guard case .setAttributes = response else {
            throw CocoaError(.coderInvalidValue)
        }
    }

    public func createDirectory(
        for itemId: NSFileProviderItemIdentifier,
        mode: mode_t = 0o700,
        ifExists: OnExists = .fail
    ) async throws {
        let response = try await perform(
            .createDirectory(
                domainId: domainId,
                itemId: itemId.rawValue,
                mode: mode,
                ifExists: ifExists
            )
        )
        guard case .createDirectory = response else {
            throw CocoaError(.coderInvalidValue)
        }
    }

    public func move(
        _ itemId: NSFileProviderItemIdentifier,
        toParent newParentId: NSFileProviderItemIdentifier,
        name newName: String,
        ifParentNotExists: OnParentNotExists = .fail
    ) async throws {
        let response = try await perform(
            .move(
                domainId: domainId,
                itemId: itemId.rawValue,
                newParentId: newParentId.rawValue,
                newName: newName,
                ifParentNotExists: ifParentNotExists
            )
        )
        guard case .move = response else {
            throw CocoaError(.coderInvalidValue)
        }
    }

    public func removeFile(
        for itemId: NSFileProviderItemIdentifier
    ) async throws {
        let response = try await perform(
            .removeFile(domainId: domainId, itemId: itemId.rawValue)
        )
        guard case .removeFile = response else {
            throw CocoaError(.coderInvalidValue)
        }
    }

    public func removeDirectory(
        for itemId: NSFileProviderItemIdentifier
    ) async throws {
        let response = try await perform(
            .removeDirectory(domainId: domainId, itemId: itemId.rawValue)
        )
        guard case .removeDirectory = response else {
            throw CocoaError(.coderInvalidValue)
        }
    }

    public func exists(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> Bool {
        let response = try await perform(
            .exists(domainId: domainId, itemId: itemId.rawValue)
        )
        guard case .exists(let exists) = response else {
            throw CocoaError(.coderInvalidValue)
        }
        return exists
    }
}
