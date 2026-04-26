import AgentKit
import Common
import Foundation

private let logger = Logger(category: "Agent")

logger.info("Starting")
let delegate = AgentListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
