import FileProvider
import OSLog
import SwiftData
import SwiftUI

public enum AuthMethod: String, Codable, Sendable {
    case password
    case privateKey
}

public struct ConnectionConfig: Sendable, Codable, Equatable {
    public let id: UUID
    public let name: String
    public let enabled: Bool
    public let host: String
    public let port: UInt16
    public let user: String
    public let path: String
    public let authMethod: AuthMethod
    public let privateKeyURL: URL?
    public let privateKeyPassphrase: String?
    public let password: String?
    
    public init(id: UUID, name: String, enabled: Bool, host: String, port: UInt16, user: String, path: String, authMethod: AuthMethod, privateKeyURL: URL?, privateKeyPassphrase: String?, password: String?) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.host = host
        self.port = port
        self.user = user
        self.path = path
        self.authMethod = authMethod
        self.privateKeyURL = privateKeyURL
        self.privateKeyPassphrase = privateKeyPassphrase
        self.password = password
    }

    public func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func fromJSON(_ json: String) -> ConnectionConfig? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(
            ConnectionConfig.self,
            from: data
        )
    }
}
