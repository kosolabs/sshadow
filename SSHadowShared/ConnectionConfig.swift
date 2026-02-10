import FileProvider
import OSLog
import SwiftData
import SwiftLibSSH
import SwiftUI

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "ConnectionConfig"
)

public struct ConnectionConfig: Codable, CustomStringConvertible, Sendable {
    public enum AuthMethod: Codable, CustomStringConvertible, Sendable {
        case none
        case password
        case privateKey(bookmark: Data)

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
        self.path = path
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
        return
            "ConnectionConfig(id: \(id), name: \(name), url: \(url), authMethod: \(authMethod))"
    }

    private var passwordKey: String {
        Keychain.shared.getPasswordKey(id: id)
    }

    public func getPassword() throws -> String {
        guard let password: String = Keychain.shared.get(passwordKey) else {
            throw ConnectionConfigError.passwordNil
        }
        return password
    }

    private var privateKeyPassphraseKey: String {
        Keychain.shared.getPrivateKeyPassphraseKey(id: id)
    }

    public func getPrivateKeyPassphrase() throws -> String? {
        guard
            let passphrase: String = Keychain.shared.get(
                privateKeyPassphraseKey
            )
        else {
            return nil
        }
        return passphrase
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
        case .password:
            return try await SSHClient.connect(
                host: config.host,
                port: config.port,
                user: config.user,
                password: try config.getPassword(),
            )
        case .privateKey(let bookmark):
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                throw SSHClientError.authenticationFailed(
                    "Failed to read private key from URL: \(url)"
                )
            }
            defer { url.stopAccessingSecurityScopedResource() }
            return try await SSHClient.connect(
                host: config.host,
                port: config.port,
                user: config.user,
                privateKeyURL: url,
                passphrase: try config.getPrivateKeyPassphrase()
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
            let result = try await sshClient.withSftp() { sftpClient in
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
