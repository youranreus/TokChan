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
        case .custom, .automaticFallback, .unavailable: return true
        case .automatic: return false
        }
    }
}

enum DashboardOperation: Equatable {
    case idle
    case submitting
    case pushing
    case pulling
    case runningAutosubmit
    case savingSettings
    case succeeded(String)
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .submitting, .pushing, .pulling, .runningAutosubmit, .savingSettings: return true
        default: return false
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
    @Published private(set) var cacheWriteErrorMessage: String?
    @Published private(set) var pushErrorMessage: String?
    @Published private(set) var cacheSavedAt: Date?
    @Published private(set) var autosubmitObservedAt: Date?
    #if DEBUG
    @Published private(set) var panelAppearanceCount = 0
    @Published private(set) var panelDisappearanceCount = 0
    #endif

    private let api: TokscaleAPIService
    private let cli: TokscaleCLIService
    private let preferencesStore: PreferencesStoring
    private let npxLocator: NpxLocating
    private let cacheStore: DashboardCacheStoring
    private let now: () -> Date
    private let refreshInterval: TimeInterval
    private let retryInterval: TimeInterval
    private let sleep: @Sendable (UInt64) async -> Void

    private enum ProfileReloadResult {
        case updated
        case failed(String)
        case superseded

        var errorMessage: String? {
            if case let .failed(message) = self { return message }
            return nil
        }
    }

    private var generation: UInt64 = 0
    private var profileRequestID = UUID()
    private var statusRequestID = UUID()
    private var profileRefreshTask: Task<ProfileReloadResult, Never>?
    private var timerTask: Task<Void, Never>?
    private var lastAutomaticAttempt: Date?
    private var isPanelVisible = false
    private var panelPresentationGeneration: UInt64 = 0
    private var operationPresentationGeneration: UInt64?
    private var suppressDashboardOperationBanner = false
    private var isLoadingServices = false
    private var cachedProfiles: [ProfilePeriod: (data: DashboardData, savedAt: Date)] = [:]

    var isLoading: Bool {
        operation.isRunning || (profileState.loadedValue == nil && (isRefreshing || isLoadingServices))
    }

    var currentAutosubmitStatus: AutosubmitStatus? { autosubmitState.loadedValue }

    var statusItemTitle: String? {
        statusItemTitle(for: preferences)
    }

    func statusItemTitle(for preferences: UserPreferences) -> String? {
        let username = preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.statusTextEnabled,
              cacheIsComplete(for: username),
              let cached = cachedProfiles[preferences.statusTextPeriod],
              cached.data.username.caseInsensitiveCompare(username) == .orderedSame else {
            return nil
        }
        let title = StatusItemTextRenderer.render(
            template: preferences.statusTextTemplate,
            data: cached.data
        )
        return title.isEmpty ? nil : title
    }

    var dashboardOperation: DashboardOperation {
        suppressDashboardOperationBanner ? .idle : operation
    }

    var diagnosticMessages: [String] {
        [
            loadErrorMessage.map { "统计读取：\($0)" },
            autosubmitLoadErrorMessage.map { "自动提交状态：\($0)" },
            cacheWriteErrorMessage.map { "本地保存：\($0)" },
            pushErrorMessage.map { "即时推送：\($0)" }
        ].compactMap { $0 }
    }

    init(
        api: TokscaleAPIService,
        cli: TokscaleCLIService,
        preferencesStore: PreferencesStoring,
        npxLocator: NpxLocating,
        cacheStore: DashboardCacheStoring,
        now: @escaping () -> Date = Date.init,
        refreshInterval: TimeInterval = 300,
        retryInterval: TimeInterval = 30,
        sleep: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.api = api
        self.cli = cli
        self.preferencesStore = preferencesStore
        self.npxLocator = npxLocator
        self.cacheStore = cacheStore
        self.now = now
        self.refreshInterval = refreshInterval
        self.retryInterval = retryInterval
        self.sleep = sleep

        let loadedPreferences = preferencesStore.load()
        preferences = loadedPreferences
        if let snapshot = cacheStore.load() {
            generation = snapshot.generation
            let username = loadedPreferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
            for entry in snapshot.profiles where !username.isEmpty
                && entry.data.username.caseInsensitiveCompare(username) == .orderedSame {
                cachedProfiles[entry.data.period] = (entry.data, entry.savedAt)
            }
            selectedPeriod = snapshot.selectedPeriod
            if let cached = cachedProfiles[selectedPeriod] {
                profileState = .loaded(cached.data)
                identityProfile = cached.data
            } else {
                identityProfile = cachedProfiles.values.first?.data
            }
            if snapshot.isCompleteBatch && cacheIsComplete { cacheSavedAt = snapshot.fetchedAt }
            if let status = snapshot.autosubmit { autosubmitState = .loaded(status) }
            autosubmitObservedAt = snapshot.autosubmitObservedAt
        }
    }

    deinit {
        profileRefreshTask?.cancel()
        timerTask?.cancel()
    }

    func npxPathStatus(for preferredPath: String) -> NpxPathStatus {
        let normalizedPath = preferredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let locatedURL = npxLocator.locate(
            preferredPath: normalizedPath.isEmpty ? nil : normalizedPath
        ) else { return .unavailable }
        guard !normalizedPath.isEmpty else { return .automatic(locatedURL) }

        let preferredURL = URL(fileURLWithPath: normalizedPath).standardizedFileURL
        if (normalizedPath as NSString).isAbsolutePath,
           preferredURL == locatedURL.standardizedFileURL {
            return .custom(locatedURL)
        }
        return .automaticFallback(locatedURL)
    }

    func panelDidAppear() {
        guard !isPanelVisible else { return }
        #if DEBUG
        panelAppearanceCount += 1
        #endif
        isPanelVisible = true
        Task { [weak self] in
            guard let self else { return }
            await self.load()
            guard self.isPanelVisible else { return }
            self.startTimerIfNeeded()
        }
    }

    func panelDidDisappear() {
        guard isPanelVisible else { return }
        #if DEBUG
        panelDisappearanceCount += 1
        #endif
        isPanelVisible = false
        panelPresentationGeneration &+= 1
        suppressDashboardOperationBanner = true
        timerTask?.cancel()
        timerTask = nil
        clearOperationMessage()
    }

    func selectPeriod(_ period: ProfilePeriod) async {
        guard selectedPeriod != period else { return }
        selectedPeriod = period
        if let cached = cachedProfiles[period], matchesUsername(cached.data.username) {
            profileState = .loaded(cached.data)
            identityProfile = cached.data
        } else {
            profileState = .loading
            _ = await reloadProfiles(force: false, automatic: true)
        }
        persistCurrentSnapshot()
    }

    func load() async {
        guard !isLoadingServices, !operation.isRunning else { return }
        let hadCachedAutosubmitStatus = autosubmitState.loadedValue != nil
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

        // Discovery may suspend while Settings changes executable/version.
        do { context = try commandContext(for: preferences) }
        catch {
            context = nil
            recordAutosubmitError(error)
        }

        if let context {
            async let profiles = reloadProfiles(force: false, automatic: true)
            if hadCachedAutosubmitStatus || autosubmitState.loadedValue == nil {
                async let status = reloadAutosubmit(context: context)
                _ = await (profiles, status)
            } else {
                _ = await profiles
            }
        } else {
            _ = await reloadProfiles(force: false, automatic: true)
        }
    }

    func refresh() async {
        guard !operation.isRunning else { return }
        invalidateProfileRefresh()
        beginOperation(.submitting)
        do {
            let context = try commandContext(for: preferences)
            _ = try await resolvedUsername(context: context)
            try await cli.submit(context: context)
            switch await reloadProfiles(force: true, automatic: false) {
            case .updated:
                completeOperation(.succeeded("用量已提交，全部范围已更新。"))
            case let .failed(message):
                completeOperation(.failed("用量已提交，但统计读取失败：\(message)"))
            case .superseded:
                completeOperation(.succeeded("用量已提交。"))
            }
        } catch { completeOperation(.failed(Self.message(for: error))) }
    }

    func retryStatistics() async {
        guard !operation.isRunning else { return }
        _ = await reloadProfiles(force: true, automatic: false)
    }

    func pushUsageNow() async {
        guard !operation.isRunning else { return }
        invalidateProfileRefresh()
        beginOperation(.pushing)
        pushErrorMessage = nil
        do {
            let context = try commandContext(for: preferences)
            _ = try await resolvedUsername(context: context)
            try await cli.submit(context: context)
            completeSilentOperation()
        } catch {
            let message = Self.message(for: error)
            pushErrorMessage = message
            completeOperation(.failed(message))
        }
    }

    func pullStatisticsNow() async {
        guard !operation.isRunning else { return }
        beginOperation(.pulling)
        switch await reloadProfiles(force: true, automatic: false) {
        case .updated, .superseded:
            completeSilentOperation()
        case let .failed(message):
            completeOperation(.failed(message))
        }
    }

    func runAutosubmitNow() async {
        guard !operation.isRunning else { return }
        invalidateProfileRefresh()
        beginOperation(.runningAutosubmit)
        do {
            let context = try commandContext(for: preferences)
            _ = try await resolvedUsername(context: context)
            try await cli.runAutosubmitNow(context: context)
            async let profiles = reloadProfiles(force: true, automatic: false)
            async let status = reloadAutosubmit(context: context)
            let (profileResult, statusError) = await (profiles, status)
            if let error = profileResult.errorMessage {
                completeOperation(.failed("自动提交已完成，但统计读取失败：\(error)"))
            } else if let statusError {
                completeOperation(.failed("自动提交已完成，但状态读取失败：\(statusError)"))
            } else {
                completeOperation(.succeeded("自动提交已完成。"))
            }
        } catch { completeOperation(.failed(Self.message(for: error))) }
    }

    func saveSettings(
        preferences newPreferences: UserPreferences,
        autosubmit configuration: AutosubmitConfiguration
    ) async -> Bool {
        guard !operation.isRunning else { return false }
        beginOperation(.savingSettings)
        do {
            let normalized = UserPreferences(
                username: newPreferences.username.trimmingCharacters(in: .whitespacesAndNewlines),
                tokscaleVersion: newPreferences.tokscaleVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                npxPath: newPreferences.npxPath.trimmingCharacters(in: .whitespacesAndNewlines),
                statusTextEnabled: newPreferences.statusTextEnabled,
                statusTextTemplate: newPreferences.statusTextTemplate,
                statusTextPeriod: newPreferences.statusTextPeriod
            )
            let context = try commandContext(for: normalized)
            guard !normalized.username.isEmpty else { throw TokscaleAPIError.invalidUsername }
            if configuration.enabled {
                try await cli.configureAutosubmit(configuration, context: context)
            } else {
                try await cli.disableAutosubmit(context: context)
            }

            invalidateProfileRefresh()
            statusRequestID = UUID()
            let accountChanged = !matchesUsername(normalized.username)
            if accountChanged {
                cachedProfiles.removeAll()
                profileState = .loading
                identityProfile = nil
                cacheSavedAt = nil
                lastAutomaticAttempt = nil
            }
            preferences = normalized
            preferencesStore.save(normalized)

            async let profiles = reloadProfiles(force: true, automatic: false)
            async let status = reloadAutosubmit(context: context)
            let (profileResult, statusError) = await (profiles, status)
            if let error = profileResult.errorMessage ?? statusError {
                completeOperation(.failed(error))
                return false
            }
            completeOperation(.succeeded("设置已保存。"))
            return true
        } catch {
            completeOperation(.failed(Self.message(for: error)))
            return false
        }
    }

    func clearOperationMessage() {
        guard !operation.isRunning else { return }
        operation = .idle
        operationPresentationGeneration = nil
    }

    private func beginOperation(_ runningOperation: DashboardOperation) {
        operationPresentationGeneration = panelPresentationGeneration
        suppressDashboardOperationBanner = !isPanelVisible
        operation = runningOperation
    }

    private func completeOperation(_ result: DashboardOperation) {
        defer { operationPresentationGeneration = nil }
        if let operationPresentationGeneration {
            suppressDashboardOperationBanner = suppressDashboardOperationBanner
                || operationPresentationGeneration != panelPresentationGeneration
                || !isPanelVisible
        }
        operation = result
    }

    private func completeSilentOperation() {
        operation = .idle
        operationPresentationGeneration = nil
    }

    private func reloadProfiles(force: Bool, automatic: Bool) async -> ProfileReloadResult {
        if automatic, operation.isRunning { return .superseded }
        if force {
            invalidateProfileRefresh()
        } else if let profileRefreshTask {
            return await profileRefreshTask.value
        }
        let username = preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            let message = Self.message(for: TokscaleAPIError.invalidUsername)
            loadErrorMessage = message
            if profileState.loadedValue == nil { profileState = .failed(message) }
            return .failed(message)
        }
        let currentTime = now()
        if !force, isFresh(at: currentTime) { return .superseded }
        if automatic, let lastAutomaticAttempt {
            let elapsed = currentTime.timeIntervalSince(lastAutomaticAttempt)
            if elapsed >= 0, elapsed < retryInterval { return .superseded }
        }

        if automatic { lastAutomaticAttempt = currentTime }
        generation &+= 1
        let requestGeneration = generation
        let requestID = UUID()
        profileRequestID = requestID
        isRefreshing = true
        loadErrorMessage = nil
        if profileState.loadedValue == nil { profileState = .loading }

        let task = Task { [weak self] () -> ProfileReloadResult in
            guard let self else { return .superseded }
            do {
                let batch = try await self.api.fetchDashboardBatch(username: username)
                try Task.checkCancellation()
                guard requestID == self.profileRequestID,
                      requestGeneration == self.generation,
                      self.matchesUsername(username),
                      batch.username.caseInsensitiveCompare(username) == .orderedSame else {
                    return .superseded
                }
                let fetchedAt = self.now()
                self.cachedProfiles = Dictionary(uniqueKeysWithValues: batch.profiles.map {
                    ($0.key, (data: $0.value, savedAt: fetchedAt))
                })
                self.cacheSavedAt = fetchedAt
                self.identityProfile = batch.profiles[self.selectedPeriod] ?? batch.profiles[.all]
                if let selected = batch.profiles[self.selectedPeriod] {
                    self.profileState = .loaded(selected)
                }
                self.persistCurrentSnapshot()
                return .updated
            } catch is CancellationError {
                return .superseded
            } catch {
                guard requestID == self.profileRequestID,
                      requestGeneration == self.generation,
                      self.matchesUsername(username) else { return .superseded }
                let message = Self.message(for: error)
                self.loadErrorMessage = message
                if self.profileState.loadedValue == nil { self.profileState = .failed(message) }
                return .failed(message)
            }
        }
        profileRefreshTask = task
        let result = await task.value
        if requestID == profileRequestID {
            profileRefreshTask = nil
            isRefreshing = false
        }
        return result
    }

    private func reloadAutosubmit(context: TokscaleCommandContext) async -> String? {
        let requestID = UUID()
        statusRequestID = requestID
        autosubmitLoadErrorMessage = nil
        do {
            let status = try await cli.autosubmitStatus(context: context)
            guard requestID == statusRequestID else { return nil }
            autosubmitState = .loaded(status)
            autosubmitObservedAt = now()
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

    private func invalidateProfileRefresh() {
        generation &+= 1
        profileRequestID = UUID()
        profileRefreshTask?.cancel()
        profileRefreshTask = nil
        isRefreshing = false
    }

    private func isFresh(at date: Date) -> Bool {
        guard cacheIsComplete, let cacheSavedAt else { return false }
        let age = date.timeIntervalSince(cacheSavedAt)
        return age >= 0 && age < refreshInterval
    }

    private var cacheIsComplete: Bool {
        let username = preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return cacheIsComplete(for: username)
    }

    private func cacheIsComplete(for username: String) -> Bool {
        Set(cachedProfiles.keys) == Set(ProfilePeriod.allCases)
            && cachedProfiles.values.allSatisfy {
                $0.data.username.caseInsensitiveCompare(username) == .orderedSame
            }
    }

    private func startTimerIfNeeded() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self, sleep] in
            while !Task.isCancelled {
                guard let self, self.isPanelVisible else { break }
                let delay = self.nextAutomaticRefreshDelay()
                let nanoseconds = UInt64(max(delay, 0.1) * 1_000_000_000)
                await sleep(nanoseconds)
                guard !Task.isCancelled, self.isPanelVisible else { break }
                guard !self.operation.isRunning else { continue }
                _ = await self.reloadProfiles(force: false, automatic: true)
            }
        }
    }

    private func nextAutomaticRefreshDelay() -> TimeInterval {
        if operation.isRunning { return 1 }
        let currentTime = now()
        var freshnessDelay: TimeInterval = 0
        if cacheIsComplete, let cacheSavedAt {
            let age = currentTime.timeIntervalSince(cacheSavedAt)
            guard age >= 0 else { return 0.1 }
            freshnessDelay = max(refreshInterval - age, 0)
        }
        var retryDelay: TimeInterval = 0
        if let lastAutomaticAttempt {
            let elapsed = currentTime.timeIntervalSince(lastAutomaticAttempt)
            guard elapsed >= 0 else { return 0.1 }
            retryDelay = max(retryInterval - elapsed, 0)
        }
        if freshnessDelay > 0 || retryDelay > 0 {
            return max(freshnessDelay, retryDelay)
        }
        return lastAutomaticAttempt == nil ? refreshInterval : 0.1
    }

    private func matchesUsername(_ username: String) -> Bool {
        preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(username) == .orderedSame
    }

    private func resolvedUsername(context: TokscaleCommandContext) async throws -> String {
        let saved = preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty { return saved }
        let discovered = try await cli.whoAmI(context: context)
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
        guard let npxURL = npxLocator.locate(
            preferredPath: preferences.npxPath.isEmpty ? nil : preferences.npxPath
        ) else { throw TokscaleCLIError.missingNpx }
        return TokscaleCommandContext(npxURL: npxURL, version: preferences.tokscaleVersion)
    }

    private func persistCurrentSnapshot() {
        let entries = ProfilePeriod.allCases.compactMap { period -> CachedDashboardProfile? in
            guard let cached = cachedProfiles[period] else { return nil }
            return CachedDashboardProfile(data: cached.data, savedAt: cached.savedAt)
        }
        let stableSavedAt = cacheSavedAt
            ?? entries.map(\.savedAt).max()
            ?? Date.distantPast
        let snapshot = DashboardCacheSnapshot(
            profile: profileState.loadedValue,
            autosubmit: autosubmitState.loadedValue,
            savedAt: stableSavedAt,
            profiles: entries,
            selectedPeriod: selectedPeriod,
            username: preferences.username,
            generation: generation,
            fetchedAt: cacheIsComplete ? cacheSavedAt : nil,
            autosubmitObservedAt: autosubmitObservedAt
        )
        do {
            try cacheStore.save(snapshot)
            cacheWriteErrorMessage = nil
        } catch {
            cacheWriteErrorMessage = Self.message(for: error)
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
