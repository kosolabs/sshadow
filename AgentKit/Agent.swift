import Common
import Foundation

private let logger = Logger(category: "Agent")

public class Agent: NSObject, AgentProtocol {
    public func sayHello(
        to name: String,
        withReply reply: @escaping (String) -> Void
    ) {
        let response = "Hello, \(name)!"
        logger.info("Received hello from: \(name)")
        reply(response)
    }
}
