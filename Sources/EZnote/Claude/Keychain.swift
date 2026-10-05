import Foundation
import Security

/// Clé API Anthropic, rangée dans le trousseau macOS.
enum Keychain {
    private static let service = "local.eznote.app"
    private static let account = "anthropic-api-key"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static var apiKey: String? {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        if SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            return String(decoding: data, as: UTF8.self)
        }
        return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }

    static func save(_ key: String) {
        SecItemDelete(query as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
