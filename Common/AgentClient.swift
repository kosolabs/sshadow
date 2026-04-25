import FileProvider
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "AgentClient")
private let serviceName = "com.kosolabs.SSHadow.Agent"

public class AgentClient {
    private let domainId: UUID
    private let connection: NSXPCConnection

    public convenience init(domainId: UUID) {
        let connection = NSXPCConnection(serviceName: serviceName)
        self.init(domainId: domainId, connection: connection)
    }

    public init(domainId: UUID, connection: NSXPCConnection) {
        self.domainId = domainId
        connection.remoteObjectInterface = NSXPCInterface(
            with: AgentProtocol.self
        )
        connection.resume()
        self.connection = connection
    }

    deinit {
        connection.invalidate()
    }

    private func perform(
        _ request: AgentRequest
    ) async throws -> AgentResponse {
        try await withCheckedThrowingContinuation { continuation in
            let proxy =
                connection.remoteObjectProxyWithErrorHandler { error in
                    continuation.resume(throwing: error)
                } as! AgentProtocol

            do {
                logger.debug("Perform: \(request)")
                let requestData = try AgentCoding.encode(request)
                proxy.perform(requestData) { responseData in
                    do {
                        let result = try AgentCoding.decode(
                            AgentResult.self,
                            from: responseData
                        )
                        continuation.resume(returning: try result.get())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
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

    public func attributes(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> SFTPAttributes {
        let response = try await perform(
            .attributes(domainId: domainId, itemId: itemId.rawValue)
        )
        guard case .attributes(let attributes) = response else {
            throw CocoaError(.coderInvalidValue)
        }
        return attributes
    }
}
