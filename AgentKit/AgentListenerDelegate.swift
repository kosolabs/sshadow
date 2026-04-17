import Common
import Foundation

public class AgentListenerDelegate: NSObject, NSXPCListenerDelegate {
    public override init() {}

    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(
            with: (any AgentProtocol).self
        )
        connection.exportedObject = Agent()
        connection.resume()
        return true
    }
}
