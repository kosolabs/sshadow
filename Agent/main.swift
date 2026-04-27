import AgentKit
import Common
import Foundation

private let logger = Logger(category: "Agent")

logger.info("Starting SSHadow agent")
let delegate = AgentListenerDelegate()
let listener = NSXPCListener(machServiceName: SSHadow.agentServiceName)
listener.delegate = delegate
listener.resume()
dispatchMain()
