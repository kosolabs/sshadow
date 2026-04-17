import Foundation

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

    private func proxy(
        errorHandler: @escaping (Error) -> Void
    ) -> AgentProtocol {
        connection.remoteObjectProxyWithErrorHandler(errorHandler)
            as! AgentProtocol
    }

    public func sayHello(to: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let service = proxy { error in
                continuation.resume(throwing: error)
            }
            logger.info("sayHello(to: \(to))")
            service.sayHello(to: to) { response in
                logger.info("Agent response: \(response)")
                continuation.resume(returning: response)
            }
        }
    }
}
