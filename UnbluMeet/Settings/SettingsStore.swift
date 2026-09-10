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
        // Stored values win; the defaults only fill blanks on first launch.
        let d = UserDefaults.standard
        liveKitURL = d.string(forKey: Key.liveKitURL) ?? Defaults.liveKitURL
        liveKitAPIKey = d.string(forKey: Key.liveKitAPIKey) ?? Defaults.liveKitAPIKey
        displayName = d.string(forKey: Key.displayName) ?? NSFullUserName()
        unbluBaseURL = d.string(forKey: Key.unbluBaseURL) ?? Defaults.unbluBaseURL
        unbluUsername = d.string(forKey: Key.unbluUsername) ?? Defaults.unbluUsername
        presenterOverlay = d.object(forKey: Key.presenterOverlay) as? Bool ?? false
        liveKitAPISecret = Self.keychainGet("liveKitAPISecret") ?? Defaults.liveKitAPISecret
        unbluPassword = Self.keychainGet("unbluPassword") ?? Defaults.unbluPassword
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
