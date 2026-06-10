import FileProvider
import SwiftData

private let logger = Logger(category: "ConnectionConfig")

public struct ConnectionConfig: Message, CustomStringConvertible {
    public enum AuthMethod: Message, CustomStringConvertible {
        case none
        case password(String)
        case privateKey(base64PrivateKey: String, passphrase: String?)

        public var description: String {
            switch self {
            case .none:
                return ".none"
            case .password:
                return ".password"
            case .privateKey:
                return ".privateKey"
            }
        }
    }

    public let id: UUID
    public let name: String
    public let host: String
    public let port: UInt16
    public let user: String
    public let path: String
    public let authMethod: AuthMethod

    public init(
        id: UUID,
        name: String,
        host: String,
        port: UInt16,
        user: String,
        path: String,
        authMethod: AuthMethod,
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.user = user
        self.path = path.hasSuffix("/") ? String(path.dropLast()) : path
        self.authMethod = authMethod
    }

    public var socket: String {
        var result = "\(host)"
        if port != 22 {
            result += ":\(port)"
        }
        return result
    }

    public var url: String {
        var result = "\(user)@\(socket)"
        if !path.isEmpty {
            result += ":\(path)"
        }
        return result
    }

    public var description: String {
        "ConnectionConfig(id: \(id), name: \(name), url: \(url), authMethod: \(authMethod))"
    }

    public func path(for subpath: String) -> String {
        [path, subpath].filter { !$0.isEmpty }.joined(separator: "/")
    }
}
