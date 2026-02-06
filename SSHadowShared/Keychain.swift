import Foundation
import OSLog
import Security

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "Keychain"
)

public struct Keychain {
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
    }

    public func set(_ key: String, to data: Data) {
        delete(key)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func get(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            return nil
        }
        return item as? Data
    }
}
