import Foundation
import Security
import Observation

@Observable
final class SettingsStore {
    /// First-launch defaults, so the app is usable without filling in the
    /// form.
    /// Blank on purpose: these are filled in Settings and kept in
    /// UserDefaults and the keychain, so no deployment's credentials live in
    /// the source.
    private enum Defaults {
        static let liveKitURL = "wss://ch.sfu.ustage.app"
        static let liveKitAPIKey = ""
        static let liveKitAPISecret = ""
        static let unbluBaseURL = "https://unblu-meet.uenv.dev/app/rest/v4"
        static let unbluUsername = "superadmin"
        static let unbluPassword = ""
    }

    private enum Key {
        static let liveKitURL = "liveKitURL"
        static let liveKitAPIKey = "liveKitAPIKey"
        static let displayName = "displayName"
        static let unbluBaseURL = "unbluBaseURL"
        static let unbluUsername = "unbluUsername"
        static let presenterOverlay = "presenterOverlay"
        static let exactIdentity = "exactIdentity"
    }

    var liveKitURL: String {
        didSet { UserDefaults.standard.set(liveKitURL, forKey: Key.liveKitURL) }
    }
    var liveKitAPIKey: String {
        didSet { UserDefaults.standard.set(liveKitAPIKey, forKey: Key.liveKitAPIKey) }
    }
    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: Key.displayName) }
    }
    var unbluBaseURL: String {
        didSet { UserDefaults.standard.set(unbluBaseURL, forKey: Key.unbluBaseURL) }
    }
    var liveKitAPISecret: String {
        didSet { Self.keychainSet("liveKitAPISecret", liveKitAPISecret) }
    }
    var unbluUsername: String {
        didSet { UserDefaults.standard.set(unbluUsername, forKey: Key.unbluUsername) }
    }
    var unbluPassword: String {
        didSet { Self.keychainSet("unbluPassword", unbluPassword) }
    }

    /// Join LiveKit as the bare Unblu person id rather than a per-session one.
    ///
    /// For testing against Unblu's own call UI, which renders a participant
    /// only when the LiveKit identity equals a person it already believes is
    /// in the call. Off by default: an identity is exclusive, so this evicts
    /// that person's Unblu session and a stale one blocks rejoining.
    var exactIdentity: Bool {
        didSet { UserDefaults.standard.set(exactIdentity, forKey: Key.exactIdentity) }
    }

    /// Draw the presenter, cut out of their camera, onto their screen share.
    var presenterOverlay: Bool {
        didSet { UserDefaults.standard.set(presenterOverlay, forKey: Key.presenterOverlay) }
    }

    var isUnbluConfigured: Bool {
        !unbluBaseURL.isEmpty && !unbluUsername.isEmpty && !unbluPassword.isEmpty
    }

    var isMediaConfigured: Bool {
        !liveKitURL.isEmpty && !liveKitAPIKey.isEmpty
            && !liveKitAPISecret.isEmpty && !displayName.isEmpty
    }

    init() {
        // A stored value wins, but only if there is something in it. A blank
        // beat the default, which is how an emptied field made the app ignore
        // the defaults for good.
        let d = UserDefaults.standard
        liveKitURL = Self.stored(d.string(forKey: Key.liveKitURL)) ?? Defaults.liveKitURL
        liveKitAPIKey = Self.stored(d.string(forKey: Key.liveKitAPIKey)) ?? Defaults.liveKitAPIKey
        displayName = Self.stored(d.string(forKey: Key.displayName)) ?? NSFullUserName()
        unbluBaseURL = Self.stored(d.string(forKey: Key.unbluBaseURL)) ?? Defaults.unbluBaseURL
        unbluUsername = Self.stored(d.string(forKey: Key.unbluUsername)) ?? Defaults.unbluUsername
        presenterOverlay = d.object(forKey: Key.presenterOverlay) as? Bool ?? false
        exactIdentity = d.object(forKey: Key.exactIdentity) as? Bool ?? false
        liveKitAPISecret = Self.stored(Self.keychainGet("liveKitAPISecret")) ?? Defaults.liveKitAPISecret
        unbluPassword = Self.stored(Self.keychainGet("unbluPassword")) ?? Defaults.unbluPassword
    }

    /// Nil for anything blank, so it falls through to the default.
    nonisolated static func stored(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    /// Forgets everything stored, so the built-in defaults apply again.
    func resetToDefaults() {
        let d = UserDefaults.standard
        for key in [Key.liveKitURL, Key.liveKitAPIKey, Key.displayName,
                    Key.unbluBaseURL, Key.unbluUsername, Key.presenterOverlay] {
            d.removeObject(forKey: key)
        }
        Self.keychainSet("liveKitAPISecret", "")
        Self.keychainSet("unbluPassword", "")
    }

    private static func keychainQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.unblu.UnbluMeet",
         kSecAttrAccount as String: account]
    }

    private static func keychainSet(_ account: String, _ value: String) {
        var query = keychainQuery(account)
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        query[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func keychainGet(_ account: String) -> String? {
        var query = keychainQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
