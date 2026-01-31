import FileProvider
import OSLog
import SwiftData
import SwiftUI

enum AuthMethod: String, Codable, Sendable {
    case password
    case privateKey
}

struct ConnectionConfigSnapshot: Sendable, Equatable {
    let id: UUID
    let name: String
    let enabled: Bool
    let host: String
    let port: UInt16
    let user: String
    let path: String
    let authMethod: AuthMethod
    let privateKeyURL: URL?
    let privateKeyPassphrase: String?
    let password: String?
}

@Model class ConnectionConfig: CustomStringConvertible {
    @Attribute(.unique) var id: UUID
    var name: String?
    var enabled: Bool
    var host: String
    var port: UInt16?
    var user: String?
    var path: String?
    var authMethod: AuthMethod
    var privateKeyBookmark: Data?

    init(
        id: UUID = UUID(),
        name: String? = nil,
        enabled: Bool = false,
        host: String = "",
        port: UInt16? = nil,
        user: String? = nil,
        path: String? = nil,
        authMethod: AuthMethod = .password
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

    var domain: NSFileProviderDomain {
        NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(id.uuidString),
            displayName: effectiveName,
        )
    }

    // MARK: - Enable / Disable

    func isEnabled() -> Bool {
        return enabled
    }

    func enable() {
        logger.notice("Enabling: \(self)")
        NSFileProviderManager.add(domain) { error in
            if let error = error {
                logger.error("Failed to enable \(self): \(error)")
            } else {
                self.enabled = true
            }
        }
    }

    func disable() {
        logger.notice("Disabling: \(self)")
        NSFileProviderManager.remove(domain) { error in
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

    func snapshot() -> ConnectionConfigSnapshot {
        ConnectionConfigSnapshot(
            id: id,
            name: effectiveName,
            enabled: enabled,
            host: host,
            port: effectivePort,
            user: effectiveUser,
            path: effectivePath,
            authMethod: authMethod,
            privateKeyURL: privateKeyURL(),
            privateKeyPassphrase: getPrivateKeyPassphrase(),
            password: getPassword()
        )
    }
}

extension ModelContext {
    func delete(connectionConfig config: ConnectionConfig) {
        config.deletePassword()
        config.deletePrivateKeyPassphrase()
        self.delete(config)
    }
}
