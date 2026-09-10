import Foundation

enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

enum FirstUseOnboardingState: Equatable {
    case modeSelection
    case discoveringIdentity
    case usernameEntry(message: String?)
    case verifying(username: String)
    case firstSubmission(username: String, message: String?)
    case submitting(username: String)
    case hidden

    var isBusy: Bool {
        switch self {
        case .discoveringIdentity, .verifying, .submitting: return true
        case .modeSelection, .usernameEntry, .firstSubmission, .hidden: return false
        }
    }
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
    case refreshingStatistics
    case loggingInCursor
    case runningAutosubmit
    case applyingAutosubmit
    case succeeded(String)
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .submitting, .refreshingStatistics, .loggingInCursor, .runningAutosubmit, .applyingAutosubmit:
            return true
        default: return false
        }
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var profileState: LoadState<DashboardData> = .idle
    @Published private(set) var firstUseOnboardingState: FirstUseOnboardingState = .usernameEntry(message: nil)
    @Published private(set) var cursorLoginState: CursorLoginState = .idle
    @Published private(set) var cursorConnectionState: CursorConnectionState = .idle
    @Published private(set) var autosubmitState: LoadState<AutosubmitStatus> = .idle
    @Published private(set) var operation: DashboardOperation = .idle
    @Published private(set) var preferences: UserPreferences
    @Published private(set) var selectedPeriod: ProfilePeriod = .all
    @Published private(set) var identityProfile: DashboardData?
    @Published private(set) var isRefreshing = false
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var sourceWarningMessage: String?
    @Published private(set) var autosubmitLoadErrorMessage: String?
    @Published private(set) var cacheWriteErrorMessage: String?
    @Published private(set) var submitErrorMessage: String?
    @Published private(set) var onlineOperationErrorMessage: String?
    @Published private(set) var configurationResetErrorMessage: String?
    @Published private(set) var cacheSavedAt: Date?
    @Published private(set) var autosubmitObservedAt: Date?
    #if DEBUG
    @Published private(set) var panelAppearanceCount = 0
    @Published private(set) var panelDisappearanceCount = 0
    #endif

    private let onlineDataSource: DashboardDataReading
    private let localDataSource: DashboardDataReading
    private let cli: TokscaleCLIService
    private let preferencesStore: PreferencesStoring
    private let npxLocator: NpxLocating
    private let cacheStore: DashboardCacheStoring
    private let now: () -> Date
    private let refreshInterval: TimeInterval
    /// Graded delays applied after consecutive automatic statistics failures; the last entry is the cap.
    private let automaticFailureBackoff: [TimeInterval]
    private let sleep: @Sendable (UInt64) async -> Void

    private enum ProfileReloadResult {
        case updated
        case profileNotFound(String)
        case failed(String)
        case superseded

        var errorMessage: String? {
            switch self {
            case let .profileNotFound(message), let .failed(message): return message
            case .updated, .superseded: return nil
            }
        }
    }

    private var generation: UInt64 = 0
    private var profileRequestID = UUID()
    private var statusRequestID = UUID()
    private var profileRefreshTask: Task<ProfileReloadResult, Never>?
    private var backgroundRefreshTask: Task<Void, Never>?
    private var autosubmitStatusTask: Task<Void, Never>?
    private var cursorStatusTask: Task<Void, Never>?
    private var cursorStatusRequestID = UUID()
    private var lastAutomaticFailure: Date?
    private var consecutiveAutomaticFailures = 0
    private var isPanelVisible = false
    private var isSettingsVisible = false
    private var settingsPresentationGeneration: UInt64 = 0
    private var hasSynchronizedOnLaunch = false
    private var lastAutosubmitStatusContext: TokscaleCommandContext?
    private var panelPresentationGeneration: UInt64 = 0
    private var operationPresentationGeneration: UInt64?
    private var suppressDashboardOperationBanner = false
    private var isLoadingServices = false
    private var cachedProfilesBySource: [DashboardDataMode: [ProfilePeriod: (data: DashboardData, savedAt: Date)]] = [:]
    private var fetchedAtBySource: [DashboardDataMode: Date] = [:]
    private var isResetting = false

    private var cachedProfiles: [ProfilePeriod: (data: DashboardData, savedAt: Date)] {
        get { cachedProfilesBySource[preferences.dataMode] ?? [:] }
        set { cachedProfilesBySource[preferences.dataMode] = newValue }
    }

    var isLoading: Bool {
        operation.isRunning || (profileState.loadedValue == nil && (isRefreshing || isLoadingServices))
    }

    var isPerformingOperation: Bool {
        operation.isRunning
            || cursorConnectionState == .checking
            || (firstUseOnboardingState.isBusy && (isLoadingServices || isRefreshing))
    }

    var currentAutosubmitStatus: AutosubmitStatus? { autosubmitState.loadedValue }

    var availableClientIDs: [String] {
        var clientIDs = preferences.hiddenClientIDs
        for sourceProfiles in cachedProfilesBySource.values {
            for cachedProfile in sourceProfiles.values {
                clientIDs.formUnion(cachedProfile.data.clients.map(\.id))
            }
        }
        return clientIDs.sorted()
    }

    var statusItemTitle: String? {
        statusItemTitle(for: preferences)
    }

    func statusItemTitle(for preferences: UserPreferences) -> String? {
        let username = preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = preferences.dataMode
        guard preferences.statusTextEnabled,
              fetchedAtBySource[source] != nil,
              cacheIsComplete(source: source),
              let cached = cachedProfilesBySource[source]?[preferences.statusTextPeriod],
              source == .local
                || cached.data.username.caseInsensitiveCompare(username) == .orderedSame else {
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
            sourceWarningMessage.map { "统计读取：\($0)" },
            autosubmitLoadErrorMessage.map { "自动提交状态：\($0)" },
            cacheWriteErrorMessage.map { "本地保存：\($0)" },
            submitErrorMessage.map { "用量提交：\($0)" },
            onlineOperationErrorMessage.map { "在线操作：\($0)" },
            configurationResetErrorMessage
        ].compactMap { $0 }
    }

    init(
        api: TokscaleAPIService,
        cli: TokscaleCLIService,
        localDataSource: DashboardDataReading = UnavailableLocalDashboardDataSource(),
        preferencesStore: PreferencesStoring,
        npxLocator: NpxLocating,
        cacheStore: DashboardCacheStoring,
        now: @escaping () -> Date = Date.init,
        refreshInterval: TimeInterval = 300,
        automaticFailureBackoff: [TimeInterval] = [30, 60, 300],
        sleep: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.onlineDataSource = OnlineDashboardDataSource(api: api)
        self.localDataSource = localDataSource
        self.cli = cli
        self.preferencesStore = preferencesStore
        self.npxLocator = npxLocator
        self.cacheStore = cacheStore
        self.now = now
        self.refreshInterval = refreshInterval
        self.automaticFailureBackoff = automaticFailureBackoff
        self.sleep = sleep

        let loadedPreferences = preferencesStore.load()
        preferences = loadedPreferences
        if let snapshot = cacheStore.load() {
            generation = snapshot.generation
            let username = loadedPreferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
            for entry in snapshot.profiles {
                if entry.source == .online {
                    guard !username.isEmpty,
                          entry.data.username.caseInsensitiveCompare(username) == .orderedSame else { continue }
                }
                cachedProfilesBySource[entry.source, default: [:]][entry.data.period] = (entry.data, entry.savedAt)
            }
            fetchedAtBySource = Dictionary(uniqueKeysWithValues: DashboardDataMode.allCases.compactMap { source in
                let account = source == .online ? username : nil
                guard snapshot.isCompleteBatch(for: source, account: account),
                      let fetchedAt = snapshot.fetchedAtBySource[source] else { return nil }
                return (source, fetchedAt)
            })
            selectedPeriod = snapshot.selectedPeriod
            if loadedPreferences.dataMode == .local || !username.isEmpty {
                cacheSavedAt = fetchedAtBySource[loadedPreferences.dataMode]
            }
            if let cached = cachedProfiles[selectedPeriod] {
                profileState = .loaded(cached.data)
                identityProfile = cached.data
            } else {
                identityProfile = cachedProfiles.values.first?.data
            }
            if let status = snapshot.autosubmit { autosubmitState = .loaded(status) }
            autosubmitObservedAt = snapshot.autosubmitObservedAt
        }
        reconcileInitialOnboardingState()
    }

    deinit {
        profileRefreshTask?.cancel()
        backgroundRefreshTask?.cancel()
        autosubmitStatusTask?.cancel()
        cursorStatusTask?.cancel()
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

    /// Starts the single application-level statistics scheduler and performs one launch read.
    ///
    /// Idempotent: the scheduler survives popover open/close cycles for the whole app lifetime.
    func startBackgroundSynchronization() {
        startStatisticsSchedulerIfNeeded()
        guard !hasSynchronizedOnLaunch else { return }
        hasSynchronizedOnLaunch = true
        Task { [weak self] in await self?.load() }
    }

    func stopBackgroundSynchronization() {
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
    }

    /// Re-evaluates statistics freshness exactly once after the machine wakes.
    ///
    /// Missed intervals are never replayed: only the current snapshot age decides whether to read.
    func reevaluateStatisticsAfterWake() async {
        _ = await reloadProfiles(force: false, automatic: true)
    }

    func panelDidAppear() {
        guard !isPanelVisible else { return }
        #if DEBUG
        panelAppearanceCount += 1
        #endif
        isPanelVisible = true
    }

    func panelDidDisappear() {
        guard isPanelVisible else { return }
        #if DEBUG
        panelDisappearanceCount += 1
        #endif
        isPanelVisible = false
        panelPresentationGeneration &+= 1
        suppressDashboardOperationBanner = true
        clearOperationMessage()
    }

    /// Called whenever the Settings window transitions from hidden to visible.
    ///
    /// Repeated callbacks inside one continuous visible period read each Settings status only once.
    func settingsDidBecomeVisible() {
        guard !isSettingsVisible else { return }
        isSettingsVisible = true
        settingsPresentationGeneration &+= 1
        cursorLoginState = .idle
        scheduleAutosubmitStatusRefresh()
        scheduleCursorStatusRefresh()
    }

    func settingsDidBecomeHidden() {
        guard isSettingsVisible else { return }
        isSettingsVisible = false
        settingsPresentationGeneration &+= 1
        invalidateCursorStatusCheck()
        cursorConnectionState = .idle
        cursorLoginState = .idle
    }

    func retryCursorStatus() {
        guard isSettingsVisible,
              cursorConnectionState.showsRetryAction else { return }
        scheduleCursorStatusRefresh()
    }

    func selectInitialMode(_ mode: DashboardDataMode) async {
        guard !preferences.hasCompletedInitialization,
              firstUseOnboardingState == .modeSelection else { return }
        var updated = preferences
        updated.dataMode = mode
        if mode == .local { updated.hasCompletedInitialization = true }
        updatePreferences(updated)
        if mode == .local {
            firstUseOnboardingState = .hidden
            _ = await reloadProfiles(force: true, automatic: false)
            if preferences.hasCompletedInitialization, preferences.dataMode == .local {
                scheduleAutosubmitStatusRefresh()
            }
        } else {
            firstUseOnboardingState = normalizedUsername.isEmpty
                ? .usernameEntry(message: nil)
                : .verifying(username: normalizedUsername)
            if !normalizedUsername.isEmpty {
                handleOnboardingProfileResult(await reloadProfiles(force: true, automatic: false))
            }
        }
    }

    func selectDataMode(_ mode: DashboardDataMode) async {
        guard !isResetting, !isPerformingOperation else { return }
        guard preferences.hasCompletedInitialization else {
            await selectInitialMode(mode)
            return
        }
        guard preferences.dataMode != mode else { return }
        invalidateProfileRefresh()
        var updated = preferences
        updated.dataMode = mode
        updated.hasCompletedInitialization = true
        preferences = updated
        preferencesStore.save(updated)
        cacheSavedAt = fetchedAtBySource[mode]
        if let cached = cachedProfiles[selectedPeriod] {
            profileState = .loaded(cached.data)
            identityProfile = cached.data
        } else {
            profileState = .idle
            identityProfile = nil
        }
        loadErrorMessage = nil
        sourceWarningMessage = nil
        clearAutomaticFailureBackoff()
        persistCurrentSnapshot()
        if mode == .online {
            reconcileInitialOnboardingState()
        } else {
            firstUseOnboardingState = .hidden
        }
        let result = await reloadProfiles(force: false, automatic: false)
        if mode == .online { handleOnboardingProfileResult(result) }
    }

    func selectPeriod(_ period: ProfilePeriod) async {
        guard selectedPeriod != period else { return }
        selectedPeriod = period
        if let cached = cachedProfiles[period], matchesCurrentSource(cached.data) {
            profileState = .loaded(cached.data)
            identityProfile = cached.data
        } else {
            profileState = .loading
            _ = await reloadProfiles(force: false, automatic: true)
        }
        persistCurrentSnapshot()
    }

    func load() async {
        guard preferences.hasCompletedInitialization,
              !isLoadingServices, !operation.isRunning else { return }
        isLoadingServices = true
        defer { isLoadingServices = false }
        if autosubmitState.loadedValue == nil { autosubmitState = .loading }

        let context: TokscaleCommandContext?
        do {
            context = try commandContext(for: preferences)
        } catch {
            context = nil
            recordAutosubmitError(error)
        }

        let shouldLoadProfiles = preferences.hasCompletedInitialization
            && (preferences.dataMode == .local || !normalizedUsername.isEmpty)
        if let context, shouldLoadProfiles {
            if preferences.dataMode == .local {
                let profileResult = await reloadProfiles(force: false, automatic: true)
                if preferences.hasCompletedInitialization, !isResetting,
                   (try? commandContext(for: preferences)) == context {
                    _ = await reloadAutosubmit(context: context)
                }
                handleOnboardingProfileResult(profileResult)
            } else {
                async let profiles = reloadProfiles(force: false, automatic: true)
                async let status = reloadAutosubmit(context: context)
                let (profileResult, _) = await (profiles, status)
                handleOnboardingProfileResult(profileResult)
            }
        } else if let context {
            _ = await reloadAutosubmit(context: context)
        } else if shouldLoadProfiles {
            handleOnboardingProfileResult(await reloadProfiles(force: false, automatic: true))
        }
    }

    func discoverIdentity() async {
        guard !isLoadingServices,
              !operation.isRunning,
              cursorConnectionState != .checking,
              normalizedUsername.isEmpty,
              case .usernameEntry = firstUseOnboardingState else { return }

        isLoadingServices = true
        firstUseOnboardingState = .discoveringIdentity
        defer { isLoadingServices = false }

        do {
            let context = try commandContext(for: preferences)
            let discovered = try await cli.whoAmI(context: context)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedUsername.isEmpty else { return }
            guard (try? commandContext(for: preferences)) == context else {
                firstUseOnboardingState = .usernameEntry(
                    message: "Tokscale 命令设置已变化，请重新识别本机登录。"
                )
                return
            }
            guard !discovered.isEmpty else { throw TokscaleAPIError.invalidUsername }
            await saveAndVerifyUsername(discovered)
        } catch {
            guard normalizedUsername.isEmpty else { return }
            firstUseOnboardingState = .usernameEntry(
                message: "无法识别 Tokscale 账号：\(Self.message(for: error))"
            )
        }
    }

    func loginCursor() async {
        guard !isPerformingOperation else { return }
        let settingsGeneration = isSettingsVisible ? settingsPresentationGeneration : nil
        let fallbackCommand = Self.cursorLoginFallbackCommand(version: preferences.tokscaleVersion)
        let context: TokscaleCommandContext
        do {
            context = try commandContext(for: preferences)
        } catch {
            cursorLoginState = .failed(
                message: Self.message(for: error),
                fallbackCommand: fallbackCommand
            )
            return
        }

        beginOperation(.loggingInCursor)
        cursorLoginState = .loggingIn
        do {
            try await cli.loginCursor(context: context)
            guard settingsGeneration == nil
                    || (isSettingsVisible
                        && settingsGeneration == settingsPresentationGeneration
                        && (try? commandContext(for: preferences)) == context) else {
                completeSilentOperation()
                return
            }
            cursorLoginState = .succeeded("Cursor 登录成功。")
            if isSettingsVisible, (try? commandContext(for: preferences)) == context {
                cursorConnectionState = .loggedIn
            }
        } catch {
            guard settingsGeneration == nil
                    || (isSettingsVisible
                        && settingsGeneration == settingsPresentationGeneration
                        && (try? commandContext(for: preferences)) == context) else {
                completeSilentOperation()
                return
            }
            cursorLoginState = .failed(
                message: Self.message(for: error),
                fallbackCommand: fallbackCommand
            )
            if isSettingsVisible { cursorConnectionState = .needsLogin }
        }
        completeSilentOperation()
    }

    func saveAndVerifyUsername(_ username: String) async {
        guard !operation.isRunning else { return }
        switch firstUseOnboardingState {
        case .verifying, .submitting: return
        case .modeSelection, .discoveringIdentity, .usernameEntry, .firstSubmission, .hidden: break
        }

        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            firstUseOnboardingState = .usernameEntry(message: "请输入 Tokscale 用户名后继续。")
            return
        }

        var updatedPreferences = preferences
        updatedPreferences.username = normalized
        updatePreferences(updatedPreferences)
        guard matchesUsername(normalized) else { return }

        firstUseOnboardingState = .verifying(username: normalized)
        handleOnboardingProfileResult(await reloadProfiles(force: true, automatic: false))
    }

    func editOnboardingUsername() {
        guard case .firstSubmission = firstUseOnboardingState else { return }
        invalidateProfileRefresh()
        firstUseOnboardingState = .usernameEntry(message: nil)
    }

    func submitFirstUsage() async {
        guard !operation.isRunning,
              cursorConnectionState != .checking,
              case let .firstSubmission(username, _) = firstUseOnboardingState,
              matchesUsername(username) else { return }

        invalidateProfileRefresh()
        beginOperation(.submitting)
        defer { completeSilentOperation() }
        firstUseOnboardingState = .submitting(username: username)
        do {
            let context = try commandContext(for: preferences)
            try await cli.submit(context: context)
            guard matchesUsername(username) else { return }
            let result = await reloadProfiles(force: true, automatic: false)
            guard matchesUsername(username) else { return }
            switch result {
            case .updated:
                if case .firstSubmission = firstUseOnboardingState {
                    firstUseOnboardingState = .firstSubmission(
                        username: username,
                        message: "提交已完成，但暂未读取到 Tokens。请检查用户名或稍后重试。"
                    )
                }
            case .profileNotFound:
                clearProfileNotFoundForOnboarding()
                firstUseOnboardingState = .firstSubmission(
                    username: username,
                    message: "提交已完成，但仍未找到该资料。请检查用户名或稍后重试。"
                )
            case let .failed(message):
                firstUseOnboardingState = .firstSubmission(
                    username: username,
                    message: "提交已完成，但统计读取失败：\(message)"
                )
            case .superseded:
                break
            }
        } catch {
            guard matchesUsername(username) else { return }
            firstUseOnboardingState = .firstSubmission(
                username: username,
                message: "提交失败：\(Self.message(for: error))"
            )
        }
    }

    /// Refreshes the selected source using its explicit panel semantics.
    func refreshCurrentSourceFromPanel() async {
        if preferences.dataMode == .online {
            await submitUsageAndRefreshStatistics()
        } else {
            guard !operation.isRunning else { return }
            beginOperation(.refreshingStatistics)
            switch await reloadProfiles(force: true, automatic: false) {
            case .updated:
                completeOperation(.succeeded("本地统计读取完成。"))
            case .superseded:
                completeSilentOperation()
            case let .profileNotFound(message), let .failed(message):
                completeOperation(.failed(message))
            }
        }
    }

    /// Uploads local usage once, then forces exactly one online statistics batch.
    func submitUsageAndRefreshStatistics() async {
        guard !operation.isRunning, cursorConnectionState != .checking else { return }
        invalidateProfileRefresh()
        beginOperation(.submitting)
        submitErrorMessage = nil
        onlineOperationErrorMessage = nil
        do {
            let context = try commandContext(for: preferences)
            let username = try resolvedUsername()
            try await cli.submit(context: context)
            // An account or CLI-context change while submit was suspended supersedes this operation.
            guard matchesUsername(username), (try? commandContext(for: preferences)) == context else {
                completeSilentOperation()
                return
            }
            switch await reloadProfiles(force: true, automatic: false, source: .online) {
            case .updated:
                completeOperation(.succeeded("用量已提交，统计读取完成。"))
            case let .profileNotFound(message), let .failed(message):
                onlineOperationErrorMessage = message
                completeOperation(.failed("用量已提交，但统计读取失败：\(message)"))
            case .superseded:
                completeOperation(.succeeded("用量已提交。"))
            }
        } catch {
            // The status menu can run this with the popover closed, so the banner may never
            // be shown; diagnostics keep the failure discoverable.
            let message = Self.message(for: error)
            submitErrorMessage = message
            completeOperation(.failed(message))
        }
    }

    func retryStatistics() async {
        guard !operation.isRunning else { return }
        _ = await reloadProfiles(force: true, automatic: false)
    }

    /// Reads one complete online statistics batch without uploading anything.
    func refreshStatisticsNow() async {
        guard !operation.isRunning else { return }
        onlineOperationErrorMessage = nil
        beginOperation(.refreshingStatistics)
        switch await reloadProfiles(force: true, automatic: false, source: .online) {
        case .updated:
            completeSilentOperation()
        case .superseded:
            completeSilentOperation()
        case let .profileNotFound(message), let .failed(message):
            onlineOperationErrorMessage = message
            completeOperation(.failed(message))
        }
    }

    func runAutosubmitNow() async {
        guard !operation.isRunning, cursorConnectionState != .checking else { return }
        invalidateProfileRefresh()
        beginOperation(.runningAutosubmit)
        do {
            let context = try commandContext(for: preferences)
            let username = try resolvedUsername()
            try await cli.runAutosubmitNow(context: context)
            // A CLI or account change while the run was suspended supersedes this operation.
            guard matchesUsername(username), (try? commandContext(for: preferences)) == context else {
                completeSilentOperation()
                return
            }
            async let profiles = reloadProfiles(force: true, automatic: false, source: .online)
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

    /// Reads autosubmit status only; it never touches statistics freshness or the cache batch.
    func refreshAutosubmitStatus() async {
        if autosubmitState.loadedValue == nil { autosubmitState = .loading }
        do {
            _ = await reloadAutosubmit(context: try commandContext(for: preferences))
        } catch {
            recordAutosubmitError(error)
        }
    }

    func updatePreferences(_ newPreferences: UserPreferences) {
        let normalized = Self.normalized(newPreferences)
        guard normalized != preferences else { return }

        let previousUsername = preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountChanged = previousUsername.caseInsensitiveCompare(normalized.username) != .orderedSame
        let modeChanged = preferences.dataMode != normalized.dataMode
        let cliContextChanged = preferences.tokscaleVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            != normalized.tokscaleVersion
            || preferences.npxPath.trimmingCharacters(in: .whitespacesAndNewlines) != normalized.npxPath

        if accountChanged {
            invalidateProfileRefresh()
            cachedProfilesBySource[.online] = [:]
            fetchedAtBySource[.online] = nil
            if preferences.dataMode == .online {
                profileState = .idle
                identityProfile = nil
                cacheSavedAt = nil
                clearAutomaticFailureBackoff()
                loadErrorMessage = nil
            }
        }
        if cliContextChanged {
            statusRequestID = UUID()
            invalidateCursorStatusCheck()
            if preferences.dataMode == .local { invalidateProfileRefresh() }
        }

        preferences = normalized
        preferencesStore.save(normalized)
        if modeChanged {
            cacheSavedAt = fetchedAtBySource[normalized.dataMode]
            if let cached = cachedProfiles[selectedPeriod] {
                profileState = .loaded(cached.data)
                identityProfile = cached.data
            } else {
                profileState = .idle
                identityProfile = nil
            }
        }
        if accountChanged && normalized.dataMode == .online {
            firstUseOnboardingState = normalized.username.isEmpty
                ? .usernameEntry(message: nil)
                : .verifying(username: normalized.username)
        }
        // Any account change must immediately persist a snapshot without the old account's
        // online profiles, even when the visible source is local.
        if accountChanged { persistCurrentSnapshot() }
        // A resolvable new CLI context makes the observed status stale, so reread status only.
        if cliContextChanged,
           let context = try? commandContext(for: normalized),
           context != lastAutosubmitStatusContext {
            scheduleAutosubmitStatusRefresh()
        }
        if cliContextChanged, isSettingsVisible {
            scheduleCursorStatusRefresh()
        }
    }

    func applyAutosubmit(_ configuration: AutosubmitConfiguration) async -> Bool {
        guard !operation.isRunning, cursorConnectionState != .checking else { return false }
        beginOperation(.applyingAutosubmit)
        do {
            let context = try commandContext(for: preferences)
            let username = preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !username.isEmpty else {
                throw TokscaleAPIError.invalidUsername
            }
            if configuration.enabled {
                try await cli.configureAutosubmit(configuration, context: context)
            } else {
                try await cli.disableAutosubmit(context: context)
            }

            // A Settings edit that landed while configure/disable was suspended owns the new context.
            guard matchesUsername(username), (try? commandContext(for: preferences)) == context else {
                completeSilentOperation()
                return false
            }

            if let statusError = await reloadAutosubmit(context: context) {
                completeOperation(.failed("自动提交设置已应用，但状态读取失败：\(statusError)"))
                return false
            }
            completeOperation(.succeeded("自动提交设置已应用。"))
            return true
        } catch {
            completeOperation(.failed(Self.message(for: error)))
            return false
        }
    }

    func resetConfiguration(disableLaunchAtLogin: () throws -> Void) async -> Bool {
        guard !isResetting, !operation.isRunning else { return false }
        configurationResetErrorMessage = nil
        isResetting = true
        let shouldResumeBackgroundSynchronization = backgroundRefreshTask != nil
        stopBackgroundSynchronization()
        invalidateProfileRefresh()
        statusRequestID = UUID()
        autosubmitStatusTask?.cancel()
        autosubmitStatusTask = nil
        invalidateCursorStatusCheck()
        do {
            try disableLaunchAtLogin()
            try preferencesStore.clear()
            try cacheStore.clear()
            cachedProfilesBySource.removeAll()
            fetchedAtBySource.removeAll()
            preferences = preferencesStore.load()
            selectedPeriod = .all
            profileState = .idle
            identityProfile = nil
            cacheSavedAt = nil
            autosubmitState = .idle
            autosubmitObservedAt = nil
            loadErrorMessage = nil
            sourceWarningMessage = nil
            autosubmitLoadErrorMessage = nil
            cacheWriteErrorMessage = nil
            submitErrorMessage = nil
            onlineOperationErrorMessage = nil
            configurationResetErrorMessage = nil
            firstUseOnboardingState = .modeSelection
            operation = .succeeded("TokChan 配置已清空。")
            isResetting = false
            if shouldResumeBackgroundSynchronization { startStatisticsSchedulerIfNeeded() }
            return true
        } catch {
            isResetting = false
            if shouldResumeBackgroundSynchronization { startStatisticsSchedulerIfNeeded() }
            let message = "清空配置失败：\(Self.message(for: error))"
            configurationResetErrorMessage = message
            operation = .failed(message)
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

    private func markInitializationComplete() {
        guard !preferences.hasCompletedInitialization else { return }
        preferences.hasCompletedInitialization = true
        preferencesStore.save(preferences)
        scheduleAutosubmitStatusRefresh()
    }

    private func reconcileInitialOnboardingState() {
        guard preferences.hasCompletedInitialization else {
            firstUseOnboardingState = .modeSelection
            return
        }
        guard preferences.dataMode == .online else {
            firstUseOnboardingState = .hidden
            return
        }
        let username = normalizedUsername
        guard !username.isEmpty else {
            firstUseOnboardingState = .usernameEntry(message: nil)
            return
        }
        guard cacheSavedAt != nil, cacheIsComplete(for: username) else {
            firstUseOnboardingState = .verifying(username: username)
            return
        }
        firstUseOnboardingState = hasUsageInCompleteCache(for: username)
            ? .hidden
            : .firstSubmission(username: username, message: nil)
    }

    private func reconcileOnboardingWithCompleteCache(username: String) {
        guard cacheSavedAt != nil, cacheIsComplete(for: username) else { return }
        if hasUsageInCompleteCache(for: username) {
            markInitializationComplete()
            firstUseOnboardingState = .hidden
        } else if firstUseOnboardingState == .usernameEntry(message: nil) {
            // Keep an explicit edit flow stable while the user is changing accounts.
        } else {
            firstUseOnboardingState = .firstSubmission(username: username, message: nil)
        }
    }

    private func hasUsageInCompleteCache(for username: String) -> Bool {
        guard cacheSavedAt != nil,
              cacheIsComplete(for: username),
              let all = cachedProfiles[.all]?.data else { return false }
        return all.totalTokens > 0
    }

    private func handleOnboardingProfileResult(_ result: ProfileReloadResult) {
        switch firstUseOnboardingState {
        case let .verifying(username):
            guard matchesUsername(username) else { return }
            switch result {
            case .updated:
                break
            case .profileNotFound:
                clearProfileNotFoundForOnboarding()
                firstUseOnboardingState = .firstSubmission(username: username, message: nil)
            case let .failed(message):
                firstUseOnboardingState = .usernameEntry(message: message)
            case .superseded:
                reconcileInitialOnboardingState()
            }
        case let .firstSubmission(username, _):
            guard matchesUsername(username) else { return }
            switch result {
            case .updated, .superseded:
                break
            case .profileNotFound:
                clearProfileNotFoundForOnboarding()
            case let .failed(message):
                firstUseOnboardingState = .firstSubmission(
                    username: username,
                    message: "统计读取失败：\(message)"
                )
            }
        case .modeSelection, .discoveringIdentity, .usernameEntry, .submitting, .hidden:
            break
        }
    }

    private func clearProfileNotFoundForOnboarding() {
        loadErrorMessage = nil
        if profileState.loadedValue == nil { profileState = .idle }
    }

    private func reloadProfiles(
        force: Bool,
        automatic: Bool,
        source requestedSource: DashboardDataMode? = nil
    ) async -> ProfileReloadResult {
        if isResetting || firstUseOnboardingState == .modeSelection { return .superseded }
        if automatic, operation.isRunning { return .superseded }
        let source = requestedSource ?? preferences.dataMode
        if force {
            invalidateProfileRefresh()
        } else if let profileRefreshTask {
            return await profileRefreshTask.value
        }
        let requestPreferences = preferences
        let username = requestPreferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if source == .online, username.isEmpty {
            if automatic { return .superseded }
            let message = Self.message(for: TokscaleAPIError.invalidUsername)
            if source == preferences.dataMode {
                loadErrorMessage = message
                if profileState.loadedValue == nil { profileState = .failed(message) }
            }
            return .failed(message)
        }
        let currentTime = now()
        if !force, isFresh(at: currentTime, source: source) { return .superseded }
        if automatic, isInAutomaticBackoff(at: currentTime) { return .superseded }

        generation &+= 1
        let requestGeneration = generation
        let requestID = UUID()
        profileRequestID = requestID
        if source == preferences.dataMode {
            isRefreshing = true
            loadErrorMessage = nil
            if profileState.loadedValue == nil { profileState = .loading }
        }

        let task = Task { [weak self] () -> ProfileReloadResult in
            guard let self else { return .superseded }
            do {
                let reader: DashboardDataReading
                let sourceRequest: DashboardSourceRequest
                let requestContext: TokscaleCommandContext?
                if source == .online {
                    reader = self.onlineDataSource
                    sourceRequest = .online(username: username)
                    requestContext = nil
                } else {
                    let context = try self.commandContext(for: requestPreferences)
                    reader = self.localDataSource
                    sourceRequest = .local(context: context, now: currentTime)
                    requestContext = context
                }
                let batch = try await reader.fetchDashboardBatch(sourceRequest)
                guard batch.source == source,
                      source == .local || batch.account?.caseInsensitiveCompare(username) == .orderedSame else {
                    return .superseded
                }
                let profiles = batch.profiles
                try Task.checkCancellation()
                let sourceIsCurrentOrExplicit = source == self.preferences.dataMode || requestedSource != nil
                let requestContextIsCurrent = source == .online
                    ? self.matchesUsername(username)
                    : (try? self.commandContext(for: self.preferences)) == requestContext
                guard requestID == self.profileRequestID,
                      requestGeneration == self.generation,
                      sourceIsCurrentOrExplicit,
                      requestContextIsCurrent else {
                    return .superseded
                }
                let fetchedAt = self.now()
                self.cachedProfilesBySource[source] = Dictionary(uniqueKeysWithValues: profiles.map {
                    ($0.key, (data: $0.value, savedAt: fetchedAt))
                })
                self.fetchedAtBySource[source] = fetchedAt
                if source == self.preferences.dataMode {
                    self.cacheSavedAt = fetchedAt
                    self.identityProfile = profiles[self.selectedPeriod] ?? profiles[.all]
                    if let selected = profiles[self.selectedPeriod] {
                        self.profileState = .loaded(selected)
                    }
                    if source == .online { self.reconcileOnboardingWithCompleteCache(username: username) }
                    self.sourceWarningMessage = batch.warnings.first
                    self.clearAutomaticFailureBackoff()
                }
                self.persistCurrentSnapshot()
                return .updated
            } catch is CancellationError {
                return .superseded
            } catch {
                let requestPreferencesAreCurrent = source == .online
                    ? self.matchesUsername(username)
                    : Self.hasSameCLIContext(requestPreferences, self.preferences)
                guard requestID == self.profileRequestID,
                      requestGeneration == self.generation,
                      requestPreferencesAreCurrent else { return .superseded }
                if automatic { self.recordAutomaticFailure(at: self.now()) }
                let message = Self.message(for: error)
                if source == self.preferences.dataMode {
                    self.loadErrorMessage = message
                    if self.profileState.loadedValue == nil { self.profileState = .failed(message) }
                }
                if Self.isProfileNotFound(error) { return .profileNotFound(message) }
                return .failed(message)
            }
        }
        profileRefreshTask = task
        let result = await task.value
        if requestID == profileRequestID {
            profileRefreshTask = nil
            if source == preferences.dataMode { isRefreshing = false }
        }
        return result
    }

    private func scheduleAutosubmitStatusRefresh() {
        guard preferences.hasCompletedInitialization, !isResetting else { return }
        autosubmitStatusTask?.cancel()
        autosubmitStatusTask = Task { [weak self] in
            // Cancellation must be observed before launching npx, not only after it returns.
            guard !Task.isCancelled else { return }
            await self?.refreshAutosubmitStatus()
        }
    }

    private func scheduleCursorStatusRefresh() {
        invalidateCursorStatusCheck()
        let requestID = UUID()
        cursorStatusRequestID = requestID
        cursorConnectionState = .checking
        cursorStatusTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if requestID == self.cursorStatusRequestID {
                    self.cursorStatusTask = nil
                }
            }
            do {
                while self.operation.isRunning || self.isLoadingServices {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                try Task.checkCancellation()
                guard requestID == self.cursorStatusRequestID, self.isSettingsVisible else { return }

                let context = try self.commandContext(for: self.preferences)
                let status = try await self.cli.cursorStatus(context: context)
                try Task.checkCancellation()
                guard requestID == self.cursorStatusRequestID,
                      self.isSettingsVisible,
                      (try? self.commandContext(for: self.preferences)) == context else { return }
                switch status {
                case .valid:
                    self.cursorConnectionState = .loggedIn
                case .unavailable:
                    self.cursorConnectionState = .needsLogin
                case .indeterminate:
                    self.cursorConnectionState = .checkFailed("无法确认 Cursor 登录状态，请重新检查。")
                }
            } catch is CancellationError {
                return
            } catch {
                guard requestID == self.cursorStatusRequestID, self.isSettingsVisible else { return }
                // Status output can contain account metadata. Keep process/context failures
                // presentation-safe instead of projecting raw CLI diagnostics into Settings.
                self.cursorConnectionState = .checkFailed("Cursor 状态检查失败，请重新检查。")
            }
        }
    }

    private func invalidateCursorStatusCheck() {
        cursorStatusRequestID = UUID()
        cursorStatusTask?.cancel()
        cursorStatusTask = nil
    }

    private func reloadAutosubmit(context: TokscaleCommandContext) async -> String? {
        let requestID = UUID()
        statusRequestID = requestID
        lastAutosubmitStatusContext = context
        autosubmitLoadErrorMessage = nil
        do {
            let status = try await cli.autosubmitStatus(context: context)
            guard requestID == statusRequestID,
                  (try? commandContext(for: preferences)) == context else { return nil }
            autosubmitState = .loaded(status)
            autosubmitObservedAt = now()
            persistCurrentSnapshot()
            return nil
        } catch {
            guard requestID == statusRequestID,
                  (try? commandContext(for: preferences)) == context else { return nil }
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

    private func isFresh(at date: Date, source: DashboardDataMode) -> Bool {
        guard cacheIsComplete(source: source), let fetchedAt = fetchedAtBySource[source] else { return false }
        let age = date.timeIntervalSince(fetchedAt)
        return age >= 0 && age < refreshInterval
    }

    private var cacheIsComplete: Bool {
        cacheIsComplete(source: preferences.dataMode)
    }

    private var normalizedUsername: String {
        preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cacheIsComplete(for username: String) -> Bool {
        cacheIsComplete(source: .online)
            && (cachedProfilesBySource[.online] ?? [:]).values.allSatisfy {
                $0.data.username.caseInsensitiveCompare(username) == .orderedSame
            }
    }

    private func cacheIsComplete(source: DashboardDataMode) -> Bool {
        Set(cachedProfilesBySource[source]?.keys.map { $0 } ?? []) == Set(ProfilePeriod.allCases)
            && fetchedAtBySource[source] != nil
    }

    private func matchesCurrentSource(_ data: DashboardData) -> Bool {
        preferences.dataMode == .local || matchesUsername(data.username)
    }

    private func startStatisticsSchedulerIfNeeded() {
        guard backgroundRefreshTask == nil else { return }
        backgroundRefreshTask = Task { [weak self, sleep] in
            while !Task.isCancelled {
                guard let self else { break }
                if !self.operation.isRunning {
                    _ = await self.reloadProfiles(force: false, automatic: true)
                }
                guard !Task.isCancelled else { break }
                let delay = self.nextAutomaticRefreshDelay()
                await sleep(UInt64(max(delay, 0.1) * 1_000_000_000))
            }
        }
    }

    /// Deadline until the next automatic evaluation is worth attempting.
    ///
    /// A rolled-back clock falls back to a full interval so the loop can never spin.
    private func nextAutomaticRefreshDelay() -> TimeInterval {
        if operation.isRunning { return 1 }
        guard preferences.hasCompletedInitialization,
              preferences.dataMode == .local || !normalizedUsername.isEmpty else { return refreshInterval }
        let currentTime = now()
        var delay: TimeInterval = 0
        if cacheIsComplete, let fetchedAt = fetchedAtBySource[preferences.dataMode] {
            let age = currentTime.timeIntervalSince(fetchedAt)
            delay = age < 0 ? refreshInterval : max(refreshInterval - age, 0)
        }
        if let lastAutomaticFailure {
            let backoff = automaticBackoffDelay()
            let elapsed = currentTime.timeIntervalSince(lastAutomaticFailure)
            delay = max(delay, elapsed < 0 ? backoff : max(backoff - elapsed, 0))
        }
        return delay > 0 ? delay : refreshInterval
    }

    private func automaticBackoffDelay() -> TimeInterval {
        guard consecutiveAutomaticFailures > 0, !automaticFailureBackoff.isEmpty else { return 0 }
        let index = min(consecutiveAutomaticFailures - 1, automaticFailureBackoff.count - 1)
        return automaticFailureBackoff[index]
    }

    private func isInAutomaticBackoff(at date: Date) -> Bool {
        guard let lastAutomaticFailure else { return false }
        let elapsed = date.timeIntervalSince(lastAutomaticFailure)
        // A rolled-back clock makes elapsed negative; stay in backoff instead of retrying immediately.
        if elapsed < 0 { return true }
        return elapsed < automaticBackoffDelay()
    }

    private func recordAutomaticFailure(at date: Date) {
        consecutiveAutomaticFailures += 1
        lastAutomaticFailure = date
    }

    private func clearAutomaticFailureBackoff() {
        consecutiveAutomaticFailures = 0
        lastAutomaticFailure = nil
    }

    private func matchesUsername(_ username: String) -> Bool {
        preferences.username.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(username) == .orderedSame
    }

    private func resolvedUsername() throws -> String {
        let saved = normalizedUsername
        guard !saved.isEmpty else { throw TokscaleAPIError.invalidUsername }
        return saved
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
        let entries = DashboardDataMode.allCases.flatMap { source in
            ProfilePeriod.allCases.compactMap { period -> CachedDashboardProfile? in
                guard let cached = cachedProfilesBySource[source]?[period] else { return nil }
                return CachedDashboardProfile(data: cached.data, savedAt: cached.savedAt, source: source)
            }
        }
        let stableSavedAt = fetchedAtBySource.values.max()
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
            fetchedAt: fetchedAtBySource[.online],
            autosubmitObservedAt: autosubmitObservedAt,
            fetchedAtBySource: fetchedAtBySource
        )
        do {
            try cacheStore.save(snapshot)
            cacheWriteErrorMessage = nil
        } catch {
            cacheWriteErrorMessage = Self.message(for: error)
        }
    }

    private static func normalized(_ preferences: UserPreferences) -> UserPreferences {
        UserPreferences(
            username: preferences.username.trimmingCharacters(in: .whitespacesAndNewlines),
            tokscaleVersion: preferences.tokscaleVersion.trimmingCharacters(in: .whitespacesAndNewlines),
            npxPath: preferences.npxPath.trimmingCharacters(in: .whitespacesAndNewlines),
            dataMode: preferences.dataMode,
            hasCompletedInitialization: preferences.hasCompletedInitialization,
            statusTextEnabled: preferences.statusTextEnabled,
            statusTextTemplate: preferences.statusTextTemplate,
            statusTextPeriod: preferences.statusTextPeriod,
            hideZeroCostModels: preferences.hideZeroCostModels,
            hiddenClientsEnabled: preferences.hiddenClientsEnabled,
            hiddenClientIDs: UserPreferences.normalizedClientIDs(preferences.hiddenClientIDs)
        )
    }

    private static func hasSameCLIContext(_ lhs: UserPreferences, _ rhs: UserPreferences) -> Bool {
        lhs.tokscaleVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            == rhs.tokscaleVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            && lhs.npxPath.trimmingCharacters(in: .whitespacesAndNewlines)
                == rhs.npxPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cursorLoginFallbackCommand(version: String) -> String {
        let normalizedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeVersion = TokscaleCommandBuilder.isValidVersion(normalizedVersion)
            ? normalizedVersion
            : "latest"
        return "npx tokscale@\(safeVersion) cursor login"
    }

    private static func isProfileNotFound(_ error: Error) -> Bool {
        guard let apiError = error as? TokscaleAPIError else { return false }
        if case .profileNotFound = apiError { return true }
        return false
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
