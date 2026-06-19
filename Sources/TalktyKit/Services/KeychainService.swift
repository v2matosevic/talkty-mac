import Foundation
import Security

/// Secure at-rest storage for secrets (the OpenRouter API key). The Mac-native
/// replacement for the Windows build's DPAPI blob in settings.json: the key lives
/// in the login Keychain, never in settings.json, and is read at point of use.
///
/// `kSecAttrAccessibleAfterFirstUnlock` keeps it readable for background launches
/// (login item) after the user has unlocked the Mac once per boot.
public enum KeychainService {
    private static let service = "hr.version2.talkty"
    private static let openRouterAccount = "openrouter-api-key"

    /// The stored OpenRouter API key, or nil if none is set. Trimmed; empty → nil.
    public static var openRouterKey: String? {
        get { read(account: openRouterAccount) }
    }

    /// Persist (or clear, when nil/empty) the OpenRouter API key.
    public static func setOpenRouterKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            write(trimmed, account: openRouterAccount)
        } else {
            delete(account: openRouterAccount)
        }
    }

    /// Whether an OpenRouter key is stored — an existence check that does NOT return the
    /// secret data, so it never triggers a Keychain access (ACL) prompt. Use this for
    /// gating UI/feature availability; only read `openRouterKey` when actually calling out.
    public static var hasOpenRouterKey: Bool { exists(account: openRouterAccount) }

    private static func exists(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,   // attributes only → no secret read, no prompt
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Generic password item helpers

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                Log.warning("Keychain read failed for \(account): OSStatus \(status)")
            }
            return nil
        }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func write(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // DELETE-then-ADD, never SecItemUpdate. Update preserves the existing item's access
        // control list (ACL); if that item was created by a differently-signed build (an
        // earlier ad-hoc build, the `security` CLI, etc.) its ACL won't trust this app, so
        // every READ pops the "enter your password to allow access" dialog. Re-adding sets a
        // fresh ACL owned by the current signing identity → the app reads it silently
        // thereafter (verified prompt-free across re-signs with the stable "Talkty Dev" cert).
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus != errSecSuccess {
            Log.error("Keychain add failed for \(account): OSStatus \(addStatus)")
        }
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Log.warning("Keychain delete failed for \(account): OSStatus \(status)")
        }
    }
}
