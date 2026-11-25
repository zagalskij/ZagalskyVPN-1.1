import Foundation
import Security

enum ConfigurationKeychain {
    static func store(_ configuration: String) throws -> Data {
        // The first keychain access group is shared by the app and its packet tunnel extension.
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Bundle.main.bundleIdentifier ?? "com.zagalsky.vpn",
            kSecAttrAccount: UUID().uuidString,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: Data(configuration.utf8),
            kSecReturnPersistentRef: true
        ]
        var result: CFTypeRef?
        guard SecItemAdd(query as CFDictionary, &result) == errSecSuccess,
              let reference = result as? Data else {
            throw TunnelIssue.keychain
        }
        return reference
    }

    static func read(_ reference: Data) throws -> String {
        let query: [CFString: Any] = [
            kSecValuePersistentRef: reference,
            kSecReturnData: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let configuration = String(data: data, encoding: .utf8) else {
            throw TunnelIssue.keychain
        }
        return configuration
    }

    static func remove(_ reference: Data) {
        let query: [CFString: Any] = [kSecValuePersistentRef: reference]
        _ = SecItemDelete(query as CFDictionary)
    }
}
