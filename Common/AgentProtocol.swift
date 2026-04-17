import Foundation

@objc public protocol AgentProtocol {
    func sayHello(to name: String, withReply reply: @escaping (String) -> Void)
}
