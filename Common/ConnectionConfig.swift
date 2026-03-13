import FileProvider
import SwiftData
import SwiftLibSSH
import SwiftUI

private let logger = Logger(category: "ConnectionConfig")

public struct ConnectionConfig:
    Codable, CustomStringConvertible, Equatable, Sendable
{
    public enum AuthMethod:
        Codable, CustomStringConvertible, Equatable, Sendable
    {
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

    public enum ConnectionConfigError: Error {
        case passwordNil
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

    public var url: String {
        var result = "\(user)@\(host)"
        if port != 22 {
            result += ":\(port)"
        }
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

    public func absoluteURL(for path: String) -> String {
        self.path.isEmpty ? "\(url):\(path)" : "\(url)/\(path)"
    }
}

extension SSHClient {
    public static func connect(
        config: ConnectionConfig
    ) async throws -> SSHClient {
        switch config.authMethod {
        case .none:
            return try await SSHClient.connect(
                host: config.host,
                port: config.port,
                user: config.user,
            )
        case .password(let password):
            return try await SSHClient.connect(
                host: config.host,
                port: config.port,
                user: config.user,
                password: password,
            )
        case .privateKey(let base64PrivateKey, let passphrase):
            return try await SSHClient.connect(
                host: config.host,
                port: config.port,
                user: config.user,
                base64PrivateKey: base64PrivateKey,
                passphrase: passphrase,
            )
        }
    }

    @discardableResult
    public static func withSession<T: Sendable>(
        config: ConnectionConfig,
        perform: @Sendable (SSHClient, SFTPClient) async throws -> T
    ) async throws -> T {
        let sshClient = try await connect(config: config)
        do {
            let result = try await sshClient.withSftp { sftpClient in
                try await perform(sshClient, sftpClient)
            }
            await sshClient.close()
            return result
        } catch {
            await sshClient.close()
            throw error
        }
    }
}
