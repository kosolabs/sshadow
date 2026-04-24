import FileProvider
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "AgentClient")
private let serviceName = "com.kosolabs.SSHadow.Agent"

public class AgentClient {
    private let connection: NSXPCConnection

    public init() {
        connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(
            with: AgentProtocol.self
        )
        connection.resume()
    }

    public init(connection: NSXPCConnection) {
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

    public func sayHello(to name: String) async throws -> String {
        let response = try await perform(.sayHello(name: name))
        guard case .sayHello(let greeting) = response else {
            throw CocoaError(.coderInvalidValue)
        }
        return greeting
    }

    public func loadConfig(id: UUID) async throws {
        let response = try await perform(.loadConfig(domainID: id))
        guard case .loadConfig = response else {
            throw CocoaError(.coderInvalidValue)
        }
    }

    public func attributes(
        domainID: UUID,
        itemID: NSFileProviderItemIdentifier
    ) async throws -> SFTPAttributes {
        let response = try await perform(
            .attributes(domainID: domainID, itemID: itemID.rawValue)
        )
        guard case .attributes(let attributes) = response else {
            throw CocoaError(.coderInvalidValue)
        }
        return attributes
    }
}
