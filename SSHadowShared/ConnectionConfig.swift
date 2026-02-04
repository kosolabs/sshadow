import FileProvider
import OSLog
import SwiftData
import SwiftUI
import SwiftLibSSH

public struct ConnectionConfig: Codable, Sendable, Equatable {
    public enum AuthMethod: Codable, Sendable, Equatable {
        case password(String)
        case privateKey(base64PrivateKey: String, passphrase: String?)
    }

    public let id: UUID
    public let name: String
    public let enabled: Bool
    public let host: String
    public let port: UInt16
    public let user: String
    public let path: String
    public let authMethod: AuthMethod

    public init(
        id: UUID,
        name: String,
        enabled: Bool,
        host: String,
        port: UInt16,
        user: String,
        path: String,
        authMethod: AuthMethod,
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.host = host
        self.port = port
        self.user = user
        self.path = path
        self.authMethod = authMethod
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

public extension SSHClient {
    static func connect(config: ConnectionConfig) async throws -> SSHClient {
        switch config.authMethod {
        case .password(let password):
            return try await SSHClient.connect(
                host: config.host,
                port: config.port,
                user: config.user,
                password: password
            )
        case .privateKey(let privateKey, let passphrase):
            return try await SSHClient.connect(
                host: config.host,
                port: config.port,
                user: config.user,
                base64PrivateKey: privateKey,
                passphrase: passphrase
            )
        }
    }

    static func withAuthenticatedClient(
        config: ConnectionConfig,
        perform: @Sendable (SSHClient) async throws -> Void
    ) async throws {
        switch config.authMethod {
        case .password(let password):
            try await SSHClient.withAuthenticatedClient(
                host: config.host,
                port: config.port,
                user: config.user,
                password: password,
                perform: perform,
            )
        case .privateKey(let privateKey, let passphrase):
            try await SSHClient.withAuthenticatedClient(
                host: config.host,
                port: config.port,
                user: config.user,
                base64PrivateKey: privateKey,
                passphrase: passphrase,
                perform: perform,
            )
        }
    }
}
