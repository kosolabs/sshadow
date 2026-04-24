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
                    case .sayHello(let name):
                        sayHello(to: name)
                    case .loadConfig(let domainId):
                        try await loadConfig(id: domainId)
                    case .attributes(let domainId, let itemId):
                        try await attributes(domainId: domainId, itemId: itemId)
                    }
                reply(try AgentCoding.encode(AgentResult.success(response)))
            } catch {
                let result = AgentResult.failure(AgentResultError(from: error))
                reply(try AgentCoding.encode(result))
            }
        }
    }

    func sayHello(to name: String) -> AgentResponse {
        .sayHello(greeting: "Hello, \(name)!")
    }

    func loadConfig(id: UUID) async throws -> AgentResponse {
        let appDB = try AppDB.open()
        guard let profile = await appDB.fetch(id: id) else {
            logger.error("Profile not found for \(id)")
            throw AgentError.profileNotFound(id)
        }
        logger.info("\(profile)")
        return .loadConfig
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
}
