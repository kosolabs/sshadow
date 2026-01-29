import SwiftData
import SwiftUI

enum AuthMethod: String, Codable, Sendable {
    case password
    case privateKey
}

@Model class ConnectionConfig {
    @Attribute(.unique) var id: UUID
    var host: String
    var port: UInt16?
    var user: String?
    var path: String?
    var authMethod: AuthMethod
    var privateKeyBookmark: Data?

    var effectivePort: UInt16 {
        port ?? 22
    }

    var effectiveUser: String {
        user ?? NSUserName()
    }

    var effectivePath: String {
        path ?? "~"
    }

    init(
        id: UUID = UUID(),
        host: String,
        port: UInt16? = nil,
        user: String? = nil,
        path: String? = nil,
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.user = user
        self.path = path
        self.authMethod = .password
    }

    var description: String {
        var result = "\(effectiveUser)@\(host)"
        if let port = port {
            result += ":\(port)"
        }
        if let path = path {
            result += ":\(path)"
        }
        return result
    }

    private var passwordKey: String {
        "password.\(id.uuidString)"
    }

    var password: String? {
        get {
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

        set {
            if let value = newValue {
                guard let data = value.data(using: .utf8) else {
                    print("Failed to encode password as UTF-8 for id: \(id)")
                    return
                }
                Keychain().set(passwordKey, to: data)
            } else {
                Keychain().delete(passwordKey)
            }
        }
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

    private var privateKeyPassphraseKey: String {
        "privateKeyPassphrase.\(id.uuidString)"
    }

    var privateKeyPassphrase: String? {
        get {
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

        set {
            if let value = newValue {
                guard let data = value.data(using: .utf8) else {
                    print(
                        "Failed to encode privateKeyPassphrase as UTF-8 for id: \(id)"
                    )
                    return
                }
                Keychain().set(privateKeyPassphraseKey, to: data)
            } else {
                Keychain().delete(privateKeyPassphraseKey)
            }
        }
    }
}
