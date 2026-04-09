import FileProvider
import SwiftData
import SwiftLibSSH
import SwiftUI

private let logger = Logger(category: "UserInfo")

public struct UserInfo: Codable, CustomStringConvertible, Sendable {
    public enum AuthMethod: Codable, CustomStringConvertible, Sendable {
        case password
        case privateKey(bookmark: Data)

        public var description: String {
            switch self {
            case .password:
                return ".password"
            case .privateKey:
                return ".privateKey"
            }
        }
    }

    public enum UserInfoError: Error {
        case passwordNil
        case encodeToDictionaryFailed
        case decodeFromDictionaryFailed
    }

    public let id: UUID
    public let name: String
    public let host: String
    public let port: UInt16
    public let user: String
    public let path: String
    public let authMethod: AuthMethod
    public let testing: Bool

    public init(
        id: UUID,
        name: String,
        host: String,
        port: UInt16,
        user: String,
        path: String,
        authMethod: AuthMethod,
        testing: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.user = user
        self.path = path
        self.authMethod = authMethod
        self.testing = testing
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
            "UserInfo(id: \(id), name: \(name), url: \(url), authMethod: \(authMethod))"
    }

    private var passwordKey: String {
        Keychain.shared.getPasswordKey(id: id)
    }

    public func getPassword() throws -> String {
        guard let password: String = Keychain.shared.get(passwordKey) else {
            throw UserInfoError.passwordNil
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

    public func toDictionary() throws -> [AnyHashable: Any] {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        return ["version": 2, "data": data]
    }

    public static func fromDictionary(
        _ dictionary: [AnyHashable: Any]?
    ) throws -> UserInfo {
        guard let dictionary = dictionary else {
            throw UserInfoError.decodeFromDictionaryFailed
        }

        guard let data = dictionary["data"] as? Data else {
            throw UserInfoError.decodeFromDictionaryFailed
        }

        let decoder = PropertyListDecoder()
        return try decoder.decode(UserInfo.self, from: data)
    }
}

extension ConnectionConfig {
    public init(from userInfo: UserInfo) throws {
        let configAuthMethod: ConnectionConfig.AuthMethod
        switch userInfo.authMethod {
        case .password:
            let password = try userInfo.getPassword()
            configAuthMethod = .password(password)
        case .privateKey(let bookmark):
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                throw SSHError.authenticationFailed(
                    message: "Failed to read private key from URL: \(url)"
                )
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard
                let base64PrivateKey = try? String(
                    data: Data(contentsOf: url),
                    encoding: .utf8
                )
            else {
                throw SSHError.authenticationFailed(
                    message:
                        "Failed to decode private key data as UTF-8 string from URL: \(url)"
                )
            }
            let passphrase = try userInfo.getPrivateKeyPassphrase()
            configAuthMethod = .privateKey(
                base64PrivateKey: base64PrivateKey,
                passphrase: passphrase
            )
        }

        self.init(
            id: userInfo.id,
            name: userInfo.name,
            host: userInfo.host,
            port: userInfo.port,
            user: userInfo.user,
            path: userInfo.path,
            authMethod: configAuthMethod
        )
    }
}
