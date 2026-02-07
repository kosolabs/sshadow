import Foundation
import OSLog
import Security

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "Keychain"
)

public protocol KeychainProviding: Sendable {
    func delete(_ key: String)
    func set(_ key: String, to data: Data)
    func set(_ key: String, to string: String)
    func get(_ key: String) -> Data?
    func get(_ key: String) -> String?
    func getPasswordKey(id: UUID) -> String
    func getPrivateKeyPassphraseKey(id: UUID) -> String
}

public final class Keychain: KeychainProviding {
    public static var shared: any KeychainProviding = Keychain()

    private let service: String
    private let accessGroup: String

    public init(
        service: String = "com.kosolabs.SSHadow",
        accessGroup: String = "group.com.kosolabs.SSHadow"
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func delete(_ key: String) {
        let query =
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key,
                kSecAttrAccessGroup: accessGroup,
                kSecUseDataProtectionKeychain: true,
            ] as [String: Any]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error(
                "SecItemDelete failed for key \(key, privacy: .public) with status: \(status)"
            )
            return
        }
    }

    public func set(_ key: String, to data: Data) {
        delete(key)

        let attributes =
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key,
                kSecAttrAccessGroup: accessGroup,
                kSecUseDataProtectionKeychain: true,
                kSecValueData: data,
                kSecAttrAccessible:
                    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ] as [String: Any]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error(
                "SecItemAdd failed for key \(key, privacy: .public) with status: \(status)"
            )
            return
        }
    }

    public func set(_ key: String, to string: String) {
        guard let data = string.data(using: .utf8) else {
            logger.error(
                "Failed to encode string as UTF-8 for key \(key, privacy: .public)"
            )
            return
        }
        set(key, to: data)
    }

    public func get(_ key: String) -> Data? {
        let query =
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key,
                kSecAttrAccessGroup: accessGroup,
                kSecUseDataProtectionKeychain: true,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne,
            ] as [String: Any]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else {
            return nil
        }
        guard status == errSecSuccess else {
            logger.error(
                "SecItemCopyMatching failed for key \(key, privacy: .public) with status: \(status)"
            )
            return nil
        }
        return item as? Data
    }

    public func get(_ key: String) -> String? {
        guard let data: Data = get(key) else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            logger.error(
                "Failed to decode data as UTF-8 for key \(key, privacy: .public)'"
            )
            return nil
        }
        return value
    }
    
    public func getPasswordKey(id: UUID) -> String {
        "password.\(id.uuidString)"
    }
    
    public func getPrivateKeyPassphraseKey(id: UUID) -> String {
        "privateKeyPassphrase.\(id.uuidString)"
    }
}
