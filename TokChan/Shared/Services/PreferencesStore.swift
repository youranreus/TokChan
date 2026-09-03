import Foundation

struct UserPreferences: Equatable {
    var username: String
    var tokscaleVersion: String
    var npxPath: String

    static let defaults = UserPreferences(
        username: "",
        tokscaleVersion: "latest",
        npxPath: ""
    )
}

protocol PreferencesStoring {
    func load() -> UserPreferences
    func save(_ preferences: UserPreferences)
}

final class UserDefaultsPreferencesStore: PreferencesStoring {
    private enum Key {
        static let username = "username"
        static let tokscaleVersion = "tokscaleVersion"
        static let npxPath = "npxPath"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> UserPreferences {
        UserPreferences(
            username: defaults.string(forKey: Key.username) ?? "",
            tokscaleVersion: defaults.string(forKey: Key.tokscaleVersion) ?? "latest",
            npxPath: defaults.string(forKey: Key.npxPath) ?? ""
        )
    }

    func save(_ preferences: UserPreferences) {
        defaults.set(preferences.username, forKey: Key.username)
        defaults.set(preferences.tokscaleVersion, forKey: Key.tokscaleVersion)
        defaults.set(preferences.npxPath, forKey: Key.npxPath)
    }
}
