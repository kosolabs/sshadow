import Common
import Foundation

public class AgentListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let appDbStorePath: URL?

    public init(appDbStorePath: URL? = nil) {
        self.appDbStorePath = appDbStorePath
    }

    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(
            with: (any AgentProtocol).self
        )
        connection.exportedObject = Agent(appDbStorePath: appDbStorePath)
        connection.resume()
        return true
    }
}
