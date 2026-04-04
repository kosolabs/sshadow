import Common
import FileProvider
import SwiftData
import SwiftUI

private let logger = Logger(category: "ConnectionProfile")

@Model
class ConnectionProfile: CustomStringConvertible {
    enum ValidationError: Error {
        case passwordNil
        case privateKeyURLNil
        case privateKeyReadFailed
        case encodeToJSONFailed
    }

    enum AuthMethod: Codable, CustomStringConvertible, Sendable {
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

    @Attribute(.unique) var id: UUID
    var name: String?
    var enabled: Bool
    var host: String
    var port: UInt16?
    var user: String?
    var path: String?
    var authMethod: AuthMethod
    var bookmark: Data?

    @Transient private var tester: ConnectionTester = DefaultConnectionTester()

    init(
        id: UUID = UUID(),
        name: String? = nil,
        enabled: Bool = false,
        host: String = "",
        port: UInt16? = nil,
        user: String? = nil,
        path: String? = nil,
        authMethod: AuthMethod = .password,
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

        self.tester = tester
    }

    // MARK: - Effective Values

    var url: String? {
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

    var effectiveName: String {
        name ?? url ?? "New Connection"
    }

    var effectivePort: UInt16 {
        port ?? 22
    }

    var effectiveUser: String {
        user ?? NSUserName()
    }

    var effectivePath: String {
        path ?? "~"
    }

    var description: String {
        "ConnectionProfile(id: \(id), name: \(name ?? "-"), enabled: \(enabled), url: \(url ?? "-"), authMethod: \(authMethod))"
    }

    // MARK: - Enable / Disable

    func isEnabled() -> Bool {
        return enabled
    }

    func enable() async throws {
        let config = try await ConnectionConfig(from: self)
        try await tester.test(config: config)
        let userInfo = try await UserInfo(from: self)
        let domain = try getDomain(with: userInfo)
        try await NSFileProviderManager.add(domain)
        try await SSHadowDB.create(domain: getDomain())
        self.enabled = true
        await logger.info("Enabled: \(self)")
    }

    func disable() async throws {
        let domain = getDomain()
        try await NSFileProviderManager.remove(domain)
        try await SSHadowDB.delete(domain: domain)
        self.enabled = false
        await logger.info("Disabled: \(self)")
    }

    // MARK: - Password Management

    private var passwordKey: String {
        Keychain.shared.getPasswordKey(id: id)
    }

    func getPassword() -> String? {
        Keychain.shared.get(passwordKey)
    }

    func setPassword(_ password: String) {
        Keychain.shared.set(passwordKey, to: password)
    }

    func deletePassword() {
        Keychain.shared.delete(passwordKey)
    }

    func privateKeyURL() -> URL? {
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

    func getPrivateKeyPassphrase() -> String? {
        Keychain.shared.get(privateKeyPassphraseKey)
    }

    func setPrivateKeyPassphrase(_ passphrase: String) {
        Keychain.shared.set(privateKeyPassphraseKey, to: passphrase)
    }

    func deletePrivateKeyPassphrase() {
        Keychain.shared.delete(privateKeyPassphraseKey)
    }

    func getDomain() -> NSFileProviderDomain {
        NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(id.uuidString),
            displayName: effectiveName,
        )
    }

    func getDomain(with userInfo: UserInfo) throws -> NSFileProviderDomain {
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
                throw ValidationError.privateKeyURLNil
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
                throw ValidationError.privateKeyURLNil
            }
            return .privateKey(bookmark: bookmark)
        }
    }
}

extension ModelContext {
    func delete(connectionConfig config: ConnectionProfile) async throws {
        if config.enabled {
            try await config.disable()
        }
        config.deletePassword()
        config.deletePrivateKeyPassphrase()
        self.delete(config)
    }
}

extension ConnectionConfig {
    init(from profile: ConnectionProfile) throws {
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
    init(from profile: ConnectionProfile) throws {
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
