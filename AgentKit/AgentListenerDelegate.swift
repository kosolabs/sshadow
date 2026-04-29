import Common
import Foundation
import XPC

private let logger = Logger(category: "AgentListener")

public enum AgentListener {
    public static func create(
        service: String = SSHadow.appServiceName,
        appDbStorePath: URL? = nil
    ) throws -> XPCListener {
        try XPCListener(service: service) { request in
            accept(request: request, appDbStorePath: appDbStorePath)
        }
    }

    public static func createAnonymous(
        appDbStorePath: URL? = nil
    ) -> XPCListener {
        XPCListener(targetQueue: nil) { request in
            accept(request: request, appDbStorePath: appDbStorePath)
        }
    }

    private static func accept(
        request: XPCListener.IncomingSessionRequest,
        appDbStorePath: URL?
    ) -> XPCListener.IncomingSessionRequest.Decision {
        let agent = Agent(appDbStorePath: appDbStorePath)
        return request.accept { message in
            let agentRequest: AgentRequest
            do {
                agentRequest = try message.decode(as: AgentRequest.self)
            } catch {
                logger.error("Failed to decode request: \(error)")
                return AgentResult.failure(AgentResultError(from: error))
            }
            Task {
                let result = await agent.handle(agentRequest)
                message.reply(result)
            }
            return nil
        }
    }
}
