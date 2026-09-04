import Foundation

enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

enum NpxPathStatus: Equatable {
    case automatic(URL)
    case custom(URL)
    case automaticFallback(URL)
    case unavailable

    var shouldExpandOverride: Bool {
        switch self {
        case .custom, .automaticFallback, .unavailable:
            return true
        case .automatic:
            return false
        }
    }
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
    @Published private(set) var selectedPeriod: ProfilePeriod = .all
    @Published private(set) var identityProfile: DashboardData?
    @Published private(set) var isRefreshing = false
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var autosubmitLoadErrorMessage: String?
    @Published private(set) var cacheSavedAt: Date?

    private let api: TokscaleAPIService
    private let cli: TokscaleCLIService
    private let preferencesStore: PreferencesStoring
    private let npxLocator: NpxLocating
    private let cacheStore: DashboardCacheStoring
    private enum ProfileReloadResult {
        case updated
        case failed(String)
        case superseded

        var errorMessage: String? {
            if case let .failed(message) = self { return message }
            return nil
        }
    }

    private var profileRequestID = UUID()
    private var statusRequestID = UUID()
    @Published private var isLoadingServices = false

    var isLoading: Bool { isRefreshing || isLoadingServices || operation.isRunning }
    private var cachedProfiles: [ProfilePeriod: (data: DashboardData, savedAt: Date)] = [:]

    var currentAutosubmitStatus: AutosubmitStatus? { autosubmitState.loadedValue }

    func npxPathStatus(for preferredPath: String) -> NpxPathStatus {
        let normalizedPath = preferredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let locatedURL = npxLocator.locate(
            preferredPath: normalizedPath.isEmpty ? nil : normalizedPath
        ) else {
            return .unavailable
        }
        guard !normalizedPath.isEmpty else { return .automatic(locatedURL) }

        let preferredURL = URL(fileURLWithPath: normalizedPath).standardizedFileURL
        if (normalizedPath as NSString).isAbsolutePath,
           preferredURL == locatedURL.standardizedFileURL {
            return .custom(locatedURL)
        }
        return .automaticFallback(locatedURL)
    }

    init(api: TokscaleAPIService, cli: TokscaleCLIService,
         preferencesStore: PreferencesStoring, npxLocator: NpxLocating,
         cacheStore: DashboardCacheStoring) {
        self.api = api
        self.cli = cli
        self.preferencesStore = preferencesStore
        self.npxLocator = npxLocator
        self.cacheStore = cacheStore
        let loadedPreferences = preferencesStore.load()
        preferences = loadedPreferences
        if let snapshot = cacheStore.load() {
            let username = loadedPreferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
            for entry in snapshot.profiles where username.isEmpty || entry.data.username.caseInsensitiveCompare(username) == .orderedSame {
                cachedProfiles[entry.data.period] = (entry.data, entry.savedAt)
            }
            selectedPeriod = snapshot.selectedPeriod
            if let cached = cachedProfiles[selectedPeriod] {
                profileState = .loaded(cached.data)
                identityProfile = cached.data
                cacheSavedAt = cached.savedAt
            } else {
                identityProfile = cachedProfiles.values.first?.data
            }
            if let status = snapshot.autosubmit { autosubmitState = .loaded(status) }
        }
    }

    func selectPeriod(_ period: ProfilePeriod) async {
        guard selectedPeriod != period else { return }
        selectedPeriod = period
        profileRequestID = UUID()
        loadErrorMessage = nil
        if let cached = cachedProfiles[period], matchesUsername(cached.data.username) {
            profileState = .loaded(cached.data)
            cacheSavedAt = cached.savedAt
            isRefreshing = false
            persistCurrentSnapshot()
            return
        } else {
            profileState = .loading
            cacheSavedAt = nil
        }
        persistCurrentSnapshot()
        _ = await reloadProfile()
    }

    func load() async {
        guard !isLoadingServices, !operation.isRunning else { return }
        guard profileState.loadedValue == nil || autosubmitState.loadedValue == nil else { return }
        isLoadingServices = true
        defer { isLoadingServices = false }
        if autosubmitState.loadedValue == nil { autosubmitState = .loading }
        var context: TokscaleCommandContext?
        do {
            context = try commandContext(for: preferences)
            if preferences.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let context {
                _ = try await resolvedUsername(context: context)
            }
        } catch {
            if preferences.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recordAutosubmitError(error)
            }
        }
        // Discovery can suspend (or fail) while Settings changes the executable/version.
        // Re-resolve even after discovery failure so a captured old context cannot win.
        do { context = try commandContext(for: preferences) }
        catch {
            context = nil
            recordAutosubmitError(error)
        }
        async let profile = loadMissingProfile()
        if autosubmitState.loadedValue == nil, let context { _ = await reloadAutosubmit(context: context) }
        _ = await profile
    }

    func refresh() async {
        guard !operation.isRunning else { return }
        operation = .submitting
        do {
            let context = try commandContext(for: preferences)
            _ = try await resolvedUsername(context: context)
            try await cli.submit(context: context)
            switch await reloadProfile() {
            case .updated: operation = .succeeded("用量已提交，资料已更新。")
            case let .failed(message): operation = .failed(message)
            case .superseded: operation = .succeeded("用量已提交。")
            }
        } catch { operation = .failed(Self.message(for: error)) }
    }

    func runAutosubmitNow() async {
        guard !operation.isRunning else { return }
        operation = .runningAutosubmit
        do {
            let context = try commandContext(for: preferences)
            _ = try await resolvedUsername(context: context)
            try await cli.runAutosubmitNow(context: context)
            async let profile = reloadProfile()
            let statusError = await reloadAutosubmit(context: context)
            let profileResult = await profile
            if let error = statusError ?? profileResult.errorMessage { operation = .failed(error) }
            else { operation = .succeeded("自动提交已完成。") }
        } catch { operation = .failed(Self.message(for: error)) }
    }

    func saveSettings(preferences newPreferences: UserPreferences,
                      autosubmit configuration: AutosubmitConfiguration) async -> Bool {
        guard !operation.isRunning else { return false }
        operation = .savingSettings
        do {
            let normalized = UserPreferences(
                username: newPreferences.username.trimmingCharacters(in: .whitespacesAndNewlines),
                tokscaleVersion: newPreferences.tokscaleVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                npxPath: newPreferences.npxPath.trimmingCharacters(in: .whitespacesAndNewlines))
            let context = try commandContext(for: normalized)
            guard !normalized.username.isEmpty else { throw TokscaleAPIError.invalidUsername }
            if configuration.enabled { try await cli.configureAutosubmit(configuration, context: context) }
            else { try await cli.disableAutosubmit(context: context) }
            // Invalidate pending reads before changing the selected account.
            profileRequestID = UUID()
            if !matchesUsername(normalized.username) {
                cachedProfiles.removeAll()
                profileState = .loading
                identityProfile = nil
                cacheSavedAt = nil
            }
            preferences = normalized
            preferencesStore.save(normalized)
            async let profile = reloadProfile()
            let statusError = await reloadAutosubmit(context: context)
            let profileResult = await profile
            if let error = statusError ?? profileResult.errorMessage {
                operation = .failed(error)
                return false
            }
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

    private func loadMissingProfile() async -> ProfileReloadResult {
        guard profileState.loadedValue == nil, !isRefreshing else { return .superseded }
        return await reloadProfile()
    }

    private func reloadProfile() async -> ProfileReloadResult {
        let requestID = UUID()
        profileRequestID = requestID
        let period = selectedPeriod
        let username = preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
        isRefreshing = true
        loadErrorMessage = nil
        if profileState.loadedValue == nil { profileState = .loading }
        defer { if requestID == profileRequestID { isRefreshing = false } }
        do {
            guard !username.isEmpty else { throw TokscaleAPIError.invalidUsername }
            let profile = try await api.fetchProfile(username: username, period: period)
            guard requestID == profileRequestID, period == selectedPeriod, matchesUsername(username) else { return .superseded }
            guard profile.period == period else { throw TokscaleAPIError.mismatchedPeriod }
            let now = Date()
            cachedProfiles[period] = (profile, now)
            profileState = .loaded(profile)
            identityProfile = profile
            cacheSavedAt = now
            persistCurrentSnapshot()
            return .updated
        } catch {
            guard requestID == profileRequestID, period == selectedPeriod, matchesUsername(username) else { return .superseded }
            let message = Self.message(for: error)
            loadErrorMessage = message
            if profileState.loadedValue == nil { profileState = .failed(message) }
            return .failed(message)
        }
    }

    private func reloadAutosubmit(context: TokscaleCommandContext) async -> String? {
        let requestID = UUID()
        statusRequestID = requestID
        autosubmitLoadErrorMessage = nil
        do {
            let status = try await cli.autosubmitStatus(context: context)
            guard requestID == statusRequestID else { return nil }
            autosubmitState = .loaded(status)
            persistCurrentSnapshot()
            return nil
        } catch {
            guard requestID == statusRequestID else { return nil }
            recordAutosubmitError(error)
            return Self.message(for: error)
        }
    }

    private func recordAutosubmitError(_ error: Error) {
        let message = Self.message(for: error)
        autosubmitLoadErrorMessage = message
        if autosubmitState.loadedValue == nil { autosubmitState = .failed(message) }
    }

    private func matchesUsername(_ username: String) -> Bool {
        preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(username) == .orderedSame
    }

    private func resolvedUsername(context: TokscaleCommandContext) async throws -> String {
        let saved = preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty { return saved }
        let discovered = try await cli.whoAmI(context: context)
        // Settings may have supplied an account while discovery was suspended.
        if preferences.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preferences.username = discovered
            preferencesStore.save(preferences)
        }
        return preferences.username
    }

    private func commandContext(for preferences: UserPreferences) throws -> TokscaleCommandContext {
        guard TokscaleCommandBuilder.isValidVersion(preferences.tokscaleVersion) else {
            throw TokscaleCLIError.invalidVersion
        }
        guard let npxURL = npxLocator.locate(preferredPath: preferences.npxPath.isEmpty ? nil : preferences.npxPath) else {
            throw TokscaleCLIError.missingNpx
        }
        return TokscaleCommandContext(npxURL: npxURL, version: preferences.tokscaleVersion)
    }

    private func persistCurrentSnapshot() {
        let profile = profileState.loadedValue
        let autosubmit = autosubmitState.loadedValue
        let entries = ProfilePeriod.allCases.compactMap { period -> CachedDashboardProfile? in
            guard let cached = cachedProfiles[period] else { return nil }
            return CachedDashboardProfile(data: cached.data, savedAt: cached.savedAt)
        }
        let snapshot = DashboardCacheSnapshot(profile: profile, autosubmit: autosubmit,
            savedAt: cacheSavedAt ?? Date(), profiles: entries, selectedPeriod: selectedPeriod)
        // The snapshot is disposable; failed writes must not mask successful reads.
        try? cacheStore.save(snapshot)
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
