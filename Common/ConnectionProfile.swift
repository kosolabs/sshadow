import FileProvider
import SwiftData
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

    public var url: String? {
        if host == "" { return nil }
        var result = "\(effectiveUser)@\(host)"
        if let port = port {
            result += ":\(port)"
        }
        if let path = path {
            result += ":\(path)"
        }
        return result
    }

    public var effectiveName: String {
        name ?? url ?? "New Connection"
    }

    public var effectivePort: UInt16 {
        port ?? 22
    }

    public var effectiveUser: String {
        user ?? NSUserName()
    }

    public var effectivePath: String {
        path ?? "~"
    }

    public var description: String {
        "ConnectionProfile(id: \(id), name: \(name ?? "-"), enabled: \(enabled), url: \(url ?? "-"), authMethod: \(authMethod))"
    }

    // MARK: - Enable / Disable

    public func isEnabled() -> Bool {
        return enabled
    }

    public func enable() async throws {
        try await NSFileProviderManager.removeAllDomains()
        let config = try ConnectionConfig(from: self)
        try await tester.test(config: config)
        let userInfo = try UserInfo(from: self)
        let domain = try getDomain(with: userInfo)
        try await NSFileProviderManager.add(domain)
        try await SSHadowDB.open(domain: domain)
        self.enabled = true
        logger.info("Enabled: \(self)")

        let agent = AgentClient()
        try await agent.loadConfig(id: id)
    }

    public func disable() async throws {
        let domain = getDomain()
        try await NSFileProviderManager.remove(domain)
        try await SSHadowDB.delete(domain: domain)
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

    public func getDomain() -> NSFileProviderDomain {
        NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(id.uuidString),
            displayName: effectiveName,
        )
    }

    public func getDomain(with userInfo: UserInfo) throws
        -> NSFileProviderDomain
    {
        let domain = getDomain()
        domain.userInfo = try userInfo.toDictionary()
        return domain
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

    fileprivate func resolveUserInfoAuthMethod() throws -> UserInfo.AuthMethod {
        switch authMethod {
        case .password:
            guard getPassword() != nil else {
                throw ValidationError.passwordNil
            }
            return .password
        case .privateKey:
            guard let bookmark = bookmark else {
                throw ValidationError.privateKeyUrlNil
            }
            return .privateKey(bookmark: bookmark)
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
            name: profile.effectiveName,
            host: profile.host,
            port: profile.effectivePort,
            user: profile.effectiveUser,
            path: profile.effectivePath,
            authMethod: profile.resolveConfigAuthMethod()
        )
    }
}

extension UserInfo {
    public init(from profile: ConnectionProfile) throws {
        try self.init(
            id: profile.id,
            name: profile.effectiveName,
            host: profile.host,
            port: profile.effectivePort,
            user: profile.effectiveUser,
            path: profile.effectivePath,
            authMethod: profile.resolveUserInfoAuthMethod()
        )
    }
}
