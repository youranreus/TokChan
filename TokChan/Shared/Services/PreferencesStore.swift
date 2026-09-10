import Foundation

enum DashboardDataMode: String, Codable, CaseIterable, Identifiable {
    case local
    case online

    var id: String { rawValue }
    var title: String { self == .local ? "本地" : "在线" }
}

struct UserPreferences: Equatable {
    static let defaultStatusTextTemplate = "{token} · {cost}"

    var username: String
    var tokscaleVersion: String
    var npxPath: String
    var statusTextEnabled: Bool
    var statusTextTemplate: String
    var statusTextPeriod: ProfilePeriod
    var hideZeroCostModels: Bool
    var hiddenClientsEnabled: Bool
    var hiddenClientIDs: Set<String>
    var dataMode: DashboardDataMode
    var hasCompletedInitialization: Bool

    init(
        username: String,
        tokscaleVersion: String,
        npxPath: String,
        dataMode: DashboardDataMode = .online,
        hasCompletedInitialization: Bool = true,
        statusTextEnabled: Bool = false,
        statusTextTemplate: String = "{token} · {cost}",
        statusTextPeriod: ProfilePeriod = .day,
        hideZeroCostModels: Bool = false,
        hiddenClientsEnabled: Bool = false,
        hiddenClientIDs: Set<String> = []
    ) {
        self.username = username
        self.tokscaleVersion = tokscaleVersion
        self.npxPath = npxPath
        self.dataMode = dataMode
        self.hasCompletedInitialization = hasCompletedInitialization
        self.statusTextEnabled = statusTextEnabled
        self.statusTextTemplate = statusTextTemplate
        self.statusTextPeriod = statusTextPeriod
        self.hideZeroCostModels = hideZeroCostModels
        self.hiddenClientsEnabled = hiddenClientsEnabled
        self.hiddenClientIDs = Self.normalizedClientIDs(hiddenClientIDs)
    }

    static func normalizedClientIDs(_ clientIDs: Set<String>) -> Set<String> {
        Set(clientIDs.compactMap { clientID in
            let normalized = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        })
    }

    static let defaults = UserPreferences(
        username: "",
        tokscaleVersion: "latest",
        npxPath: "",
        dataMode: .local,
        hasCompletedInitialization: false
    )
}

protocol PreferencesStoring {
    func load() -> UserPreferences
    func save(_ preferences: UserPreferences)
    func clear() throws
}

extension PreferencesStoring {
    func clear() throws { save(.defaults) }
}

final class UserDefaultsPreferencesStore: PreferencesStoring {
    private enum Key {
        static let username = "username"
        static let tokscaleVersion = "tokscaleVersion"
        static let npxPath = "npxPath"
        static let statusTextEnabled = "statusTextEnabled"
        static let statusTextTemplate = "statusTextTemplate"
        static let statusTextPeriod = "statusTextPeriod"
        static let hideZeroCostModels = "hideZeroCostModels"
        static let hiddenClientsEnabled = "hiddenClientsEnabled"
        static let hiddenClientIDs = "hiddenClientIDs"
        static let dataMode = "dashboardDataMode"
        static let hasCompletedInitialization = "hasCompletedInitialization"

        static let all = [
            username, tokscaleVersion, npxPath, statusTextEnabled, statusTextTemplate,
            statusTextPeriod, hideZeroCostModels, hiddenClientsEnabled, hiddenClientIDs,
            dataMode, hasCompletedInitialization
        ]
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> UserPreferences {
        UserPreferences(
            username: defaults.string(forKey: Key.username) ?? "",
            tokscaleVersion: defaults.string(forKey: Key.tokscaleVersion) ?? "latest",
            npxPath: defaults.string(forKey: Key.npxPath) ?? "",
            dataMode: defaults.string(forKey: Key.dataMode).flatMap(DashboardDataMode.init(rawValue:)) ?? .local,
            hasCompletedInitialization: defaults.object(forKey: Key.hasCompletedInitialization) as? Bool ?? false,
            statusTextEnabled: defaults.object(forKey: Key.statusTextEnabled) as? Bool ?? false,
            statusTextTemplate: defaults.string(forKey: Key.statusTextTemplate)
                ?? UserPreferences.defaultStatusTextTemplate,
            statusTextPeriod: defaults.string(forKey: Key.statusTextPeriod)
                .flatMap(ProfilePeriod.init(rawValue:)) ?? .day,
            hideZeroCostModels: defaults.object(forKey: Key.hideZeroCostModels) as? Bool ?? false,
            hiddenClientsEnabled: defaults.object(forKey: Key.hiddenClientsEnabled) as? Bool ?? false,
            hiddenClientIDs: Set(defaults.stringArray(forKey: Key.hiddenClientIDs) ?? [])
        )
    }

    func save(_ preferences: UserPreferences) {
        defaults.set(preferences.username, forKey: Key.username)
        defaults.set(preferences.tokscaleVersion, forKey: Key.tokscaleVersion)
        defaults.set(preferences.npxPath, forKey: Key.npxPath)
        defaults.set(preferences.dataMode.rawValue, forKey: Key.dataMode)
        defaults.set(preferences.hasCompletedInitialization, forKey: Key.hasCompletedInitialization)
        defaults.set(preferences.statusTextEnabled, forKey: Key.statusTextEnabled)
        defaults.set(preferences.statusTextTemplate, forKey: Key.statusTextTemplate)
        defaults.set(preferences.statusTextPeriod.rawValue, forKey: Key.statusTextPeriod)
        defaults.set(preferences.hideZeroCostModels, forKey: Key.hideZeroCostModels)
        defaults.set(preferences.hiddenClientsEnabled, forKey: Key.hiddenClientsEnabled)
        defaults.set(
            UserPreferences.normalizedClientIDs(preferences.hiddenClientIDs).sorted(),
            forKey: Key.hiddenClientIDs
        )
    }

    func clear() throws {
        Key.all.forEach(defaults.removeObject(forKey:))
    }
}
