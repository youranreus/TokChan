import Foundation

enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

enum DashboardOperation: Equatable {
    case idle
    case submitting
    case runningAutosubmit
    case savingSettings
    case succeeded(String)
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .submitting, .runningAutosubmit, .savingSettings:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var profileState: LoadState<DashboardData> = .idle
    @Published private(set) var autosubmitState: LoadState<AutosubmitStatus> = .idle
    @Published private(set) var operation: DashboardOperation = .idle
    @Published private(set) var preferences: UserPreferences
    @Published private(set) var isRefreshing = false
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var cacheSavedAt: Date?

    private let api: TokscaleAPIService
    private let cli: TokscaleCLIService
    private let preferencesStore: PreferencesStoring
    private let npxLocator: NpxLocating
    private let cacheStore: DashboardCacheStoring
    private var loadID = UUID()

    var currentAutosubmitStatus: AutosubmitStatus? {
        guard case let .loaded(status) = autosubmitState else { return nil }
        return status
    }

    init(
        api: TokscaleAPIService,
        cli: TokscaleCLIService,
        preferencesStore: PreferencesStoring,
        npxLocator: NpxLocating,
        cacheStore: DashboardCacheStoring
    ) {
        self.api = api
        self.cli = cli
        self.preferencesStore = preferencesStore
        self.npxLocator = npxLocator
        self.cacheStore = cacheStore

        let loadedPreferences = preferencesStore.load()
        preferences = loadedPreferences
        if let snapshot = cacheStore.load() {
            let selectedUsername = loadedPreferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
            if let profile = snapshot.profile,
               selectedUsername.isEmpty
                || profile.username.caseInsensitiveCompare(selectedUsername) == .orderedSame {
                profileState = .loaded(profile)
            }
            if let autosubmit = snapshot.autosubmit {
                autosubmitState = .loaded(autosubmit)
            }
            cacheSavedAt = snapshot.savedAt
        }
    }

    func load() async {
        guard !isRefreshing else { return }
        let requestID = UUID()
        loadID = requestID
        isRefreshing = true
        loadErrorMessage = nil
        if profileState.loadedValue == nil { profileState = .loading }
        if autosubmitState.loadedValue == nil { autosubmitState = .loading }
        defer {
            if loadID == requestID { isRefreshing = false }
        }

        var loadErrors: [String] = []

        var workingPreferences = preferences
        let context: TokscaleCommandContext?
        do {
            context = try commandContext(for: workingPreferences)
        } catch {
            context = nil
            let message = Self.message(for: error)
            if autosubmitState.loadedValue == nil { autosubmitState = .failed(message) }
            loadErrors.append(message)
        }

        if workingPreferences.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let context {
            do {
                workingPreferences.username = try await cli.whoAmI(context: context)
                preferences = workingPreferences
                preferencesStore.save(workingPreferences)
            } catch {
                if loadID == requestID {
                    let message = Self.message(for: error)
                    if profileState.loadedValue == nil { profileState = .failed(message) }
                    loadErrors.append(message)
                }
            }
        }

        let username = workingPreferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileTask = username.isEmpty ? nil : Task { [api] in
            try await api.fetchProfile(username: username)
        }
        let statusTask = context.map { commandContext in
            Task { [cli] in
                try await cli.autosubmitStatus(context: commandContext)
            }
        }

        if let profileTask {
            do {
                let profile = try await profileTask.value
                if loadID == requestID {
                    profileState = .loaded(profile)
                    persistCurrentSnapshot()
                }
            } catch {
                if loadID == requestID {
                    let message = Self.message(for: error)
                    if profileState.loadedValue == nil { profileState = .failed(message) }
                    loadErrors.append(message)
                }
            }
        }

        if let statusTask {
            do {
                let status = try await statusTask.value
                if loadID == requestID {
                    autosubmitState = .loaded(status)
                    persistCurrentSnapshot()
                }
            } catch {
                if loadID == requestID {
                    let message = Self.message(for: error)
                    if autosubmitState.loadedValue == nil { autosubmitState = .failed(message) }
                    loadErrors.append(message)
                }
            }
        }

        if loadID == requestID, !loadErrors.isEmpty {
            loadErrorMessage = Array(Set(loadErrors)).sorted().joined(separator: "\n")
        }
    }

    func refresh() async {
        guard !operation.isRunning else { return }
        do {
            let context = try commandContext(for: preferences)
            let username = try await resolvedUsername(context: context)
            operation = .submitting
            try await cli.submit(context: context)
            profileState = .loaded(try await api.fetchProfile(username: username))
            persistCurrentSnapshot()
            operation = .succeeded("用量已提交，资料已更新。")
        } catch {
            operation = .failed(Self.message(for: error))
        }
    }

    func runAutosubmitNow() async {
        guard !operation.isRunning else { return }
        do {
            let context = try commandContext(for: preferences)
            let username = try await resolvedUsername(context: context)
            operation = .runningAutosubmit
            try await cli.runAutosubmitNow(context: context)

            async let status = cli.autosubmitStatus(context: context)
            async let profile = api.fetchProfile(username: username)
            let (newStatus, newProfile) = try await (status, profile)
            autosubmitState = .loaded(newStatus)
            profileState = .loaded(newProfile)
            persistCurrentSnapshot()
            operation = .succeeded("自动提交已完成。")
        } catch {
            operation = .failed(Self.message(for: error))
        }
    }

    func saveSettings(
        preferences newPreferences: UserPreferences,
        autosubmit configuration: AutosubmitConfiguration
    ) async -> Bool {
        guard !operation.isRunning else { return false }
        do {
            let normalizedPreferences = UserPreferences(
                username: newPreferences.username.trimmingCharacters(in: .whitespacesAndNewlines),
                tokscaleVersion: newPreferences.tokscaleVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                npxPath: newPreferences.npxPath.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let context = try commandContext(for: normalizedPreferences)
            guard !normalizedPreferences.username.isEmpty else {
                throw TokscaleAPIError.invalidUsername
            }

            operation = .savingSettings
            if configuration.enabled {
                try await cli.configureAutosubmit(configuration, context: context)
            } else {
                try await cli.disableAutosubmit(context: context)
            }

            preferences = normalizedPreferences
            preferencesStore.save(normalizedPreferences)
            autosubmitState = .loaded(try await cli.autosubmitStatus(context: context))
            profileState = .loaded(try await api.fetchProfile(username: normalizedPreferences.username))
            persistCurrentSnapshot()
            operation = .succeeded("设置已保存。")
            return true
        } catch {
            operation = .failed(Self.message(for: error))
            return false
        }
    }

    func clearOperationMessage() {
        guard !operation.isRunning else { return }
        operation = .idle
    }

    private func resolvedUsername(context: TokscaleCommandContext) async throws -> String {
        let saved = preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty { return saved }
        let discovered = try await cli.whoAmI(context: context)
        preferences.username = discovered
        preferencesStore.save(preferences)
        return discovered
    }

    private func commandContext(for preferences: UserPreferences) throws -> TokscaleCommandContext {
        guard TokscaleCommandBuilder.isValidVersion(preferences.tokscaleVersion) else {
            throw TokscaleCLIError.invalidVersion
        }
        guard let npxURL = npxLocator.locate(
            preferredPath: preferences.npxPath.isEmpty ? nil : preferences.npxPath
        ) else {
            throw TokscaleCLIError.missingNpx
        }
        return TokscaleCommandContext(npxURL: npxURL, version: preferences.tokscaleVersion)
    }

    private func persistCurrentSnapshot() {
        let profile = profileState.loadedValue
        let autosubmit = autosubmitState.loadedValue
        guard profile != nil || autosubmit != nil else { return }

        let snapshot = DashboardCacheSnapshot(
            profile: profile,
            autosubmit: autosubmit,
            savedAt: Date()
        )
        do {
            try cacheStore.save(snapshot)
            cacheSavedAt = snapshot.savedAt
        } catch {
            // Cache failures must never block fresh data or Tokscale operations.
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

extension LoadState {
    var loadedValue: Value? {
        guard case let .loaded(value) = self else { return nil }
        return value
    }
}
