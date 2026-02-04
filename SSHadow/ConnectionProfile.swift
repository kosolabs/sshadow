import FileProvider
import OSLog
import SSHadowShared
import SwiftData
import SwiftUI

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "ConnectionProfile"
)

@Model class ConnectionProfile: CustomStringConvertible {
    enum ValidationError: Error {
        case passwordNil
        case privateKeyURLNil
        case privateKeyReadFailed
        case encodeToJSONFailed
    }

    enum AuthMethod: Codable, Sendable, Equatable {
        case password
        case privateKey
    }

    @Attribute(.unique) var id: UUID
    var name: String?
    var enabled: Bool
    var host: String
    var port: UInt16?
    var user: String?
    var path: String?
    var authMethod: AuthMethod
    var privateKeyBookmark: Data?

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
        var result = ""
        if let user = user {
            result += "\(user)@"
        }
        result += host
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
        "ConnectionConfig(id: \(id), name: \(name ?? "-"), enabled: \(enabled), url: \(url ?? "-"), authMethod: \(authMethod))"
    }

    func getDomain() -> NSFileProviderDomain {
        NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(id.uuidString),
            displayName: effectiveName,
        )
    }

    func getDomain(with config: ConnectionConfig) throws -> NSFileProviderDomain
    {
        let domain = getDomain()

        guard let data = try? JSONEncoder().encode(config) else {
            throw ValidationError.encodeToJSONFailed
        }
        guard let val = String(data: data, encoding: .utf8) else {
            throw ValidationError.encodeToJSONFailed
        }

        domain.userInfo = ["connectionConfig": val]
        return domain
    }

    func getConfigAuthMethod() throws -> ConnectionConfig.AuthMethod {
        switch authMethod {
        case .password:
            guard let password = getPassword() else {
                throw ValidationError.passwordNil
            }
            return ConnectionConfig.AuthMethod.password(password)
        case .privateKey:
            guard let url = privateKeyURL() else {
                throw ValidationError.privateKeyURLNil
            }
            guard url.startAccessingSecurityScopedResource() else {
                throw ValidationError.privateKeyReadFailed
            }
            let privateKey = try String(contentsOf: url, encoding: .utf8)
            url.stopAccessingSecurityScopedResource()

            return ConnectionConfig.AuthMethod.privateKey(
                base64PrivateKey: privateKey,
                passphrase: getPrivateKeyPassphrase()
            )
        }
    }

    func getConfig() throws -> ConnectionConfig {
        try ConnectionConfig(
            id: id,
            name: effectiveName,
            enabled: enabled,
            host: host,
            port: effectivePort,
            user: effectiveUser,
            path: effectivePath,
            authMethod: getConfigAuthMethod()
        )
    }

    // MARK: - Enable / Disable

    func isEnabled() -> Bool {
        return enabled
    }

    func enable() async throws {
        await logger.info("Enabling: \(self)")
        let config = try getConfig()
        try await tester.test(config: config)
        let domain = try getDomain(with: config)
        try await NSFileProviderManager.add(domain)
        self.enabled = true
    }

    func disable() {
        logger.info("Disabling: \(self)")
        NSFileProviderManager.remove(getDomain()) { error in
            if let error = error {
                logger.error(
                    "Failed to disable \(self): \(error)"
                )
            } else {
                self.enabled = false
            }
        }
    }

    // MARK: - Password Management

    private var passwordKey: String {
        "password.\(id.uuidString)"
    }

    func getPassword() -> String? {
        guard let data = Keychain().get(passwordKey) else {
            return nil
        }
        do {
            return try data.decoded(as: .utf8)
        } catch {
            print("Failed to decode password from UTF-8 for id: \(id)")
            return nil
        }
    }

    func setPassword(_ password: String) {
        guard let data = password.data(using: .utf8) else {
            print("Failed to encode password as UTF-8 for id: \(id)")
            return
        }
        Keychain().set(passwordKey, to: data)
    }

    func deletePassword() {
        Keychain().delete(passwordKey)
    }

    func privateKeyURL() -> URL? {
        guard let bookmark = privateKeyBookmark else {
            return nil
        }
        do {
            var isStale = false
            return try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            print("Failed to resolve bookmark data for id: \(id)")
            return nil
        }
    }

    // MARK: - Private Key Passphrase Management

    private var privateKeyPassphraseKey: String {
        "privateKeyPassphrase.\(id.uuidString)"
    }

    func getPrivateKeyPassphrase() -> String? {
        guard let data = Keychain().get(privateKeyPassphraseKey) else {
            return nil
        }
        do {
            return try data.decoded(as: .utf8)
        } catch {
            print(
                "Failed to decode privateKeyPassphrase from UTF-8 for id: \(id)"
            )
            return nil
        }
    }

    func setPrivateKeyPassphrase(_ passphrase: String) {
        guard let data = passphrase.data(using: .utf8) else {
            print(
                "Failed to encode privateKeyPassphrase as UTF-8 for id: \(id)"
            )
            return
        }
        Keychain().set(privateKeyPassphraseKey, to: data)
    }

    func deletePrivateKeyPassphrase() {
        Keychain().delete(privateKeyPassphraseKey)
    }
}

extension ModelContext {
    func delete(connectionConfig config: ConnectionProfile) {
        config.deletePassword()
        config.deletePrivateKeyPassphrase()
        self.delete(config)
    }
}
