import Foundation
import Security

struct Keychain {
    let service: String?

    init(service: String? = nil) {
        self.service = service ?? Bundle.main.bundleIdentifier
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as Any?,
            kSecAttrAccount as String: key,
        ].compactMapValues { $0 }
        SecItemDelete(query as CFDictionary)
    }

    func set(_ key: String, to data: Data) {
        delete(key)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as Any?,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ].compactMapValues { $0 }

        SecItemAdd(attributes as CFDictionary, nil)
    }

    func get(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as Any?,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ].compactMapValues { $0 }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            return nil
        }
        return item as? Data
    }
}
