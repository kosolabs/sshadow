import FileProvider
import SwiftData
import SwiftLibSSH
import SwiftUI

private let logger = Logger(category: "ConnectionProfile")

@Model
public class ConnectionProfile: CustomStringConvertible {
    public enum ValidationError: Error {
        case passwordNil
        case privateKeyUrlNil
        case privateKeyReadFailed
        case encodeToJsonFailed
    }

    public enum AuthMethod: Codable, CustomStringConvertible, Sendable {
        case password
        case privateKey

        public var description: String {
            switch self {
            case .password:
                return ".password"
            case .privateKey:
                return ".privateKey"
            }
        }
    }

    @Attribute(.unique) public var id: UUID
    public var name: String?
    public var enabled: Bool
    public var host: String
    public var port: UInt16?
    public var user: String?
    public var path: String?
    public var authMethod: AuthMethod
    public var bookmark: Data?

    @Transient private var tester: ConnectionTester = DefaultConnectionTester()

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        enabled: Bool = false,
        host: String = "",
        port: UInt16? = nil,
        user: String? = nil,
        path: String? = nil,
        authMethod: AuthMethod = .password,
        bookmark: Data? = nil,
        tester: ConnectionTester = DefaultConnectionTester()
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.host = host
        self.port = port
        self.user = user
        self.path = path
        self.authMethod = authMethod
        self.bookmark = bookmark

        self.tester = tester
    }

    // MARK: - Effective Values

    public var socket: String {
        var result = "\(host)"
        if let port = port, port != 22 {
            result += ":\(port)"
        }
        return result
    }

    public var url: String {
        var result = "\(effectiveUser)@\(socket)"
        if !effectivePath.isEmpty {
            result += ":\(effectivePath)"
        }
        return result
    }

    public var displayName: String {
        host.isEmpty ? "New Connection" : name ?? url
    }

    public var displayUrl: String {
        host.isEmpty ? "New Connection" : url
    }

    public var effectivePort: UInt16 {
        port ?? 22
    }

    public var effectiveUser: String {
        user ?? NSUserName()
    }

    public var effectivePath: String {
        let p = path ?? ""
        return p.count > 1 && p.hasSuffix("/") ? String(p.dropLast()) : p
    }

    public func path(for subpath: String) -> String {
        if effectivePath == "/" {
            return "/\(subpath)"
        }
        return [effectivePath, subpath].filter { !$0.isEmpty }.joined(
            separator: "/"
        )
    }

    public func absoluteUrl(for path: String) -> String {
        effectivePath.isEmpty ? "\(url):\(path)" : "\(url)/\(path)"
    }

    public var description: String {
        "ConnectionProfile(id: \(id), name: \(name ?? "-"), enabled: \(enabled), url: \(url), authMethod: \(authMethod))"
    }

    public var domain: NSFileProviderDomain {
        NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(id.uuidString),
            displayName: displayName,
        )
    }

    // MARK: - Enable / Disable

    public func isEnabled() -> Bool {
        return enabled
    }

    public func enable() async throws {
        let agent = AgentClient(domainId: id)
        let config = try ConnectionConfig(from: self)
        try await tester.test(config: config)
        try await agent.initDomain()
        try await NSFileProviderManager.add(domain)

        self.enabled = true
        logger.info("Enabled: \(self)")
    }

    public func disable() async throws {
        let agent = AgentClient(domainId: id)
        try await NSFileProviderManager.remove(domain)
        try await agent.deinitDomain()

        self.enabled = false
        logger.info("Disabled: \(self)")
    }

    // MARK: - Password Management

    private var passwordKey: String {
        Keychain.shared.getPasswordKey(id: id)
    }

    public func getPassword() -> String? {
        Keychain.shared.get(passwordKey)
    }

    public func setPassword(_ password: String) {
        Keychain.shared.set(passwordKey, to: password)
    }

    public func deletePassword() {
        Keychain.shared.delete(passwordKey)
    }

    public func privateKeyUrl() -> URL? {
        guard let bookmark = bookmark else {
            return nil
        }
        do {
            var isStale = false
            return try URL(
                resolvingBookmarkData: bookmark,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            logger.error(
                "Failed to resolve bookmark data for id: \(self.id), error: \(error)"
            )
            return nil
        }
    }

    public func getBase64PrivateKey() throws -> String {
        guard let bookmark = bookmark else {
            throw ValidationError.privateKeyUrlNil
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            bookmarkDataIsStale: &isStale
        )
        guard url.startAccessingSecurityScopedResource() else {
            throw ValidationError.privateKeyReadFailed
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard
            let base64PrivateKey = try? String(
                data: Data(contentsOf: url),
                encoding: .utf8
            )
        else {
            throw ValidationError.privateKeyReadFailed
        }
        return base64PrivateKey
    }

    // MARK: - Private Key Passphrase Management

    private var privateKeyPassphraseKey: String {
        Keychain.shared.getPrivateKeyPassphraseKey(id: id)
    }

    public func getPrivateKeyPassphrase() -> String? {
        Keychain.shared.get(privateKeyPassphraseKey)
    }

    public func setPrivateKeyPassphrase(_ passphrase: String) {
        Keychain.shared.set(privateKeyPassphraseKey, to: passphrase)
    }

    public func deletePrivateKeyPassphrase() {
        Keychain.shared.delete(privateKeyPassphraseKey)
    }

    fileprivate func resolveConfigAuthMethod() throws
        -> ConnectionConfig.AuthMethod
    {
        switch authMethod {
        case .password:
            guard let password = getPassword() else {
                throw ValidationError.passwordNil
            }
            return .password(password)
        case .privateKey:
            guard let bookmark = bookmark else {
                throw ValidationError.privateKeyUrlNil
            }
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                throw ValidationError.privateKeyReadFailed
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard
                let base64PrivateKey = try? String(
                    data: Data(contentsOf: url),
                    encoding: .utf8
                )
            else {
                throw ValidationError.privateKeyReadFailed
            }
            let passphrase = getPrivateKeyPassphrase()
            return .privateKey(
                base64PrivateKey: base64PrivateKey,
                passphrase: passphrase
            )
        }
    }
}

extension ModelContext {
    public func delete(
        connectionConfig config: ConnectionProfile
    ) async throws {
        if config.enabled {
            try await config.disable()
        }
        config.deletePassword()
        config.deletePrivateKeyPassphrase()
        self.delete(config)
    }
}

extension ConnectionConfig {
    public init(from profile: ConnectionProfile) throws {
        try self.init(
            id: profile.id,
            name: profile.displayName,
            host: profile.host,
            port: profile.effectivePort,
            user: profile.effectiveUser,
            path: profile.effectivePath,
            authMethod: profile.resolveConfigAuthMethod()
        )
    }
}

extension SSHClient {
    public static func connect(
        profile: ConnectionProfile
    ) async throws -> SSHClient {
        switch profile.authMethod {
        case .password:
            guard let password = profile.getPassword() else {
                throw ConnectionProfile.ValidationError.passwordNil
            }
            return try await SSHClient.connect(
                host: profile.host,
                port: profile.effectivePort,
                user: profile.effectiveUser,
                password: password,
            )
        case .privateKey:
            let base64PrivateKey = try profile.getBase64PrivateKey()
            let passphrase = profile.getPrivateKeyPassphrase()
            return try await SSHClient.connect(
                host: profile.host,
                port: profile.effectivePort,
                user: profile.effectiveUser,
                base64PrivateKey: base64PrivateKey,
                passphrase: passphrase,
            )
        }
    }

    @discardableResult
    public static func withSession<T: Sendable>(
        profile: ConnectionProfile,
        perform: @Sendable (SSHClient, SFTPClient) async throws -> T
    ) async throws -> T {
        let sshClient = try await connect(profile: profile)
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
