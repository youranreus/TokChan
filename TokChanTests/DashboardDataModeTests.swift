import XCTest
@testable import TokChan

@MainActor
final class DashboardDataModeTests: XCTestCase {
    func testLocalPanelRefreshReadsLocalSourceWithoutSubmitOrPublicAPI() async throws {
        let events = ModeEventRecorder()
        let local = ModeLocalSource(events: events, tokens: 42)
        let model = makeModel(mode: .local, events: events, local: local)
        model.panelDidAppear()

        await model.refreshCurrentSourceFromPanel()

        XCTAssertEqual(model.profileState.loadedValue?.totalTokens, 42)
        let recordedEvents = await events.snapshot()
        XCTAssertEqual(recordedEvents, ["local"])
    }

    func testModeSwitchIsIgnoredDuringExplicitRefresh() async {
        let events = ModeEventRecorder()
        let source = SuspendedModeLocalSource(events: events)
        let model = makeModel(mode: .local, events: events, local: source)
        let refresh = Task { await model.refreshCurrentSourceFromPanel() }
        await source.waitUntilStarted()

        await model.selectDataMode(.online)

        XCTAssertEqual(model.preferences.dataMode, .local)
        await source.resume(tokens: 42)
        await refresh.value
        XCTAssertEqual(model.profileState.loadedValue?.totalTokens, 42)
    }

    func testOnlineMenuReadWhileLocalOnlyUpdatesOnlineCache() async throws {
        let events = ModeEventRecorder()
        let model = makeModel(mode: .local, events: events, local: ModeLocalSource(events: events, tokens: 42))
        await model.retryStatistics()
        XCTAssertEqual(model.profileState.loadedValue?.totalTokens, 42)

        await model.refreshStatisticsNow()

        XCTAssertEqual(model.preferences.dataMode, .local)
        XCTAssertEqual(model.profileState.loadedValue?.totalTokens, 42)
        let recordedEvents = await events.snapshot()
        XCTAssertEqual(recordedEvents, ["local", "online"])

        await model.selectDataMode(.online)
        XCTAssertEqual(model.profileState.loadedValue?.totalTokens, 99)
    }

    func testOnlineMenuSubmitWhileLocalOrdersSubmitBeforeReadAndOnlyUpdatesOnlineCache() async {
        let events = ModeEventRecorder()
        let model = makeModel(mode: .local, events: events, local: ModeLocalSource(events: events, tokens: 42))
        await model.retryStatistics()

        await model.submitUsageAndRefreshStatistics()

        XCTAssertEqual(model.preferences.dataMode, .local)
        XCTAssertEqual(model.profileState.loadedValue?.totalTokens, 42)
        let recordedEvents = await events.snapshot()
        XCTAssertEqual(recordedEvents, ["local", "submit", "online"])

        await model.selectDataMode(.online)
        XCTAssertEqual(model.profileState.loadedValue?.totalTokens, 99)
    }

    func testOnlineReadFailureAfterMenuSubmitWhileLocalRemainsDiscoverable() async {
        let events = ModeEventRecorder()
        let model = makeModel(
            mode: .local,
            events: events,
            local: ModeLocalSource(events: events, tokens: 42),
            apiError: ModeFailure.unavailable
        )
        await model.retryStatistics()

        await model.submitUsageAndRefreshStatistics()

        XCTAssertEqual(model.profileState.loadedValue?.totalTokens, 42)
        XCTAssertTrue(model.diagnosticMessages.contains { $0.hasPrefix("在线操作：") })
        let recordedEvents = await events.snapshot()
        XCTAssertEqual(recordedEvents, ["local", "submit", "online"])
    }

    func testOnlineMenuActionsWithoutUsernamePointToSettingsAndDoNotTransfer() async {
        let events = ModeEventRecorder()
        let model = DashboardViewModel(
            api: ModeAPI(events: events),
            cli: ModeCLI(events: events),
            localDataSource: ModeLocalSource(events: events, tokens: 42),
            preferencesStore: ModePreferences(UserPreferences(
                username: "",
                tokscaleVersion: "latest",
                npxPath: "",
                dataMode: .local,
                hasCompletedInitialization: true
            )),
            npxLocator: ModeNpxLocator(),
            cacheStore: ModeCache()
        )

        await model.submitUsageAndRefreshStatistics()
        await model.refreshStatisticsNow()

        let recordedEvents = await events.snapshot()
        XCTAssertTrue(recordedEvents.isEmpty)
        XCTAssertTrue(model.diagnosticMessages.contains { $0.contains("设置") && $0.contains("用户名") })
    }

    func testUninitializedInstallStartsAtModeSelectionAndLocalChoiceCompletesImmediately() async {
        let events = ModeEventRecorder()
        let preferences = ModePreferences(UserPreferences(
            username: "existing-online-user",
            tokscaleVersion: "latest",
            npxPath: "",
            dataMode: .local,
            hasCompletedInitialization: false
        ))
        let model = DashboardViewModel(
            api: ModeAPI(events: events),
            cli: ModeCLI(events: events),
            localDataSource: ModeLocalSource(events: events, tokens: 42),
            preferencesStore: preferences,
            npxLocator: ModeNpxLocator(),
            cacheStore: ModeCache()
        )

        XCTAssertEqual(model.firstUseOnboardingState, .modeSelection)
        await model.selectInitialMode(.local)

        XCTAssertEqual(model.firstUseOnboardingState, .hidden)
        XCTAssertTrue(preferences.value.hasCompletedInitialization)
        XCTAssertEqual(preferences.value.username, "existing-online-user")
        let recordedEvents = await events.snapshot()
        XCTAssertEqual(recordedEvents, ["local"])
    }

    func testStatusTitleUsesIncomingModeInsteadOfPreviouslyStoredMode() {
        let onlineDate = Date(timeIntervalSince1970: 100)
        let localDate = Date(timeIntervalSince1970: 200)
        let onlineProfiles = modeProfiles(tokens: 99, username: "online-user")
        let localProfiles = modeProfiles(tokens: 42, username: "")
        let snapshot = DashboardCacheSnapshot(
            profile: onlineProfiles[.all],
            autosubmit: nil,
            savedAt: localDate,
            profiles: DashboardDataMode.allCases.flatMap { source in
                let profiles = source == .online ? onlineProfiles : localProfiles
                let savedAt = source == .online ? onlineDate : localDate
                return ProfilePeriod.allCases.compactMap { period in
                    profiles[period].map {
                        CachedDashboardProfile(data: $0, savedAt: savedAt, source: source)
                    }
                }
            },
            selectedPeriod: .all,
            username: "online-user",
            fetchedAt: onlineDate,
            fetchedAtBySource: [.online: onlineDate, .local: localDate]
        )
        let events = ModeEventRecorder()
        let model = makeModel(
            mode: .online,
            events: events,
            local: ModeLocalSource(events: events, tokens: 42),
            cache: ModeCache(snapshot: snapshot),
            statusTextEnabled: true
        )
        var incoming = model.preferences
        incoming.dataMode = .local

        XCTAssertEqual(model.statusItemTitle(for: incoming), "42 · $0.42")
    }

    func testAccountChangeWhileLocalPersistsSnapshotWithoutOldOnlineProfiles() async {
        let savedAt = Date(timeIntervalSince1970: 100)
        let onlineProfiles = modeProfiles(tokens: 99, username: "online-user")
        let snapshot = DashboardCacheSnapshot(
            profile: onlineProfiles[.all],
            autosubmit: nil,
            savedAt: savedAt,
            profiles: ProfilePeriod.allCases.compactMap { period in
                onlineProfiles[period].map {
                    CachedDashboardProfile(data: $0, savedAt: savedAt, source: .online)
                }
            },
            selectedPeriod: .all,
            username: "online-user",
            fetchedAt: savedAt,
            fetchedAtBySource: [.online: savedAt]
        )
        let events = ModeEventRecorder()
        let cache = RecordingModeCache(snapshot: snapshot)
        let model = makeModel(
            mode: .local,
            events: events,
            local: ModeLocalSource(events: events, tokens: 42),
            cache: cache
        )
        await model.retryStatistics()
        // The hydrated online batch is persisted from the local mode too.
        XCTAssertTrue(cache.lastSaved?.profiles.contains { $0.source == .online } ?? false)

        var updated = model.preferences
        updated.username = "new-online-user"
        model.updatePreferences(updated)

        let persisted = cache.lastSaved
        XCTAssertNotNil(persisted)
        XCTAssertFalse(persisted?.profiles.contains { $0.source == .online } ?? true)
        XCTAssertNil(persisted?.fetchedAtBySource[.online])
        XCTAssertTrue(persisted?.profiles.contains { $0.source == .local } ?? false)
    }

    func testOnlineMenuFailureWhileLocalPreservesVisibleDataAndAddsDiagnostic() async {
        let events = ModeEventRecorder()
        let model = makeModel(
            mode: .local,
            events: events,
            local: ModeLocalSource(events: events, tokens: 42),
            apiError: ModeFailure.unavailable
        )
        await model.retryStatistics()

        await model.refreshStatisticsNow()

        XCTAssertEqual(model.profileState.loadedValue?.totalTokens, 42)
        XCTAssertEqual(model.preferences.dataMode, .local)
        XCTAssertTrue(model.diagnosticMessages.contains { $0.contains("在线操作") })
    }

    func testLateLocalResultCannotPublishAfterCLIContextChanges() async {
        let events = ModeEventRecorder()
        let source = SuspendedModeLocalSource(events: events)
        let model = makeModel(mode: .local, events: events, local: source)

        let refresh = Task { await model.retryStatistics() }
        await source.waitUntilStarted()
        var updated = model.preferences
        updated.tokscaleVersion = "4.15.1"
        model.updatePreferences(updated)
        await source.resume(tokens: 42)
        await refresh.value

        XCTAssertNil(model.profileState.loadedValue)
        let recordedEvents = await events.snapshot()
        XCTAssertEqual(recordedEvents, ["local"])
    }

    func testLateLocalResultCannotRepublishAfterConfigurationReset() async {
        let events = ModeEventRecorder()
        let source = SuspendedModeLocalSource(events: events)
        let preferences = ModePreferences(UserPreferences(
            username: "online-user",
            tokscaleVersion: "latest",
            npxPath: "",
            dataMode: .local,
            hasCompletedInitialization: true
        ))
        let model = DashboardViewModel(
            api: ModeAPI(events: events),
            cli: ModeCLI(events: events),
            localDataSource: source,
            preferencesStore: preferences,
            npxLocator: ModeNpxLocator(),
            cacheStore: ModeCache()
        )
        let refresh = Task { await model.retryStatistics() }
        await source.waitUntilStarted()

        let resetSucceeded = await model.resetConfiguration(disableLaunchAtLogin: {})
        await source.resume(tokens: 42)
        await refresh.value

        XCTAssertTrue(resetSucceeded)
        XCTAssertEqual(model.firstUseOnboardingState, .modeSelection)
        XCTAssertNil(model.profileState.loadedValue)
        XCTAssertNil(model.cacheSavedAt)
        XCTAssertFalse(model.preferences.hasCompletedInitialization)
    }

    func testLocalLoadCannotStartAutosubmitStatusAfterConfigurationReset() async {
        let events = ModeEventRecorder()
        let source = SuspendedModeLocalSource(events: events)
        let preferences = ModePreferences(UserPreferences(
            username: "online-user",
            tokscaleVersion: "latest",
            npxPath: "",
            dataMode: .local,
            hasCompletedInitialization: true
        ))
        let model = DashboardViewModel(
            api: ModeAPI(events: events),
            cli: StatusRecordingModeCLI(events: events),
            localDataSource: source,
            preferencesStore: preferences,
            npxLocator: ModeNpxLocator(),
            cacheStore: ModeCache()
        )
        let load = Task { await model.load() }
        await source.waitUntilStarted()

        let resetSucceeded = await model.resetConfiguration(disableLaunchAtLogin: {})
        await source.resume(tokens: 42)
        await load.value

        XCTAssertTrue(resetSucceeded)
        let recordedEvents = await events.snapshot()
        XCTAssertEqual(recordedEvents, ["local"])
        XCTAssertEqual(model.firstUseOnboardingState, .modeSelection)
        XCTAssertNil(model.currentAutosubmitStatus)
    }

    func testConfigurationResetClearsOwnedStateAndReturnsToWelcome() async {
        let events = ModeEventRecorder()
        let preferences = ModePreferences(UserPreferences(
            username: "keep-only-until-reset",
            tokscaleVersion: "4.15.1",
            npxPath: "/tmp/npx",
            dataMode: .local,
            hasCompletedInitialization: true,
            statusTextEnabled: true
        ))
        let cache = ModeCache()
        let model = DashboardViewModel(
            api: ModeAPI(events: events),
            cli: ModeCLI(events: events),
            localDataSource: ModeLocalSource(events: events, tokens: 42),
            preferencesStore: preferences,
            npxLocator: ModeNpxLocator(),
            cacheStore: cache
        )
        await model.retryStatistics()
        var disabledLoginItem = false

        let succeeded = await model.resetConfiguration { disabledLoginItem = true }

        XCTAssertTrue(succeeded)
        XCTAssertTrue(disabledLoginItem)
        XCTAssertTrue(preferences.didClear)
        XCTAssertTrue(cache.didClear)
        XCTAssertEqual(model.preferences.dataMode, .local)
        XCTAssertFalse(model.preferences.hasCompletedInitialization)
        XCTAssertEqual(model.firstUseOnboardingState, .modeSelection)
        XCTAssertNil(model.profileState.loadedValue)
        XCTAssertEqual(model.selectedPeriod, .day)

        model.panelDidAppear()
        XCTAssertEqual(model.selectedPeriod, .day)
    }

    func testConfigurationResetFailureKeepsStateAndCanRetry() async {
        let events = ModeEventRecorder()
        let preferences = ModePreferences(UserPreferences(
            username: "online-user",
            tokscaleVersion: "latest",
            npxPath: "",
            dataMode: .local,
            hasCompletedInitialization: true
        ))
        let cache = ModeCache()
        cache.clearError = ModeFailure.unavailable
        let model = DashboardViewModel(
            api: ModeAPI(events: events),
            cli: ModeCLI(events: events),
            localDataSource: ModeLocalSource(events: events, tokens: 42),
            preferencesStore: preferences,
            npxLocator: ModeNpxLocator(),
            cacheStore: cache
        )
        await model.retryStatistics()

        let firstResetSucceeded = await model.resetConfiguration(disableLaunchAtLogin: {})
        XCTAssertFalse(firstResetSucceeded)
        XCTAssertEqual(model.profileState.loadedValue?.totalTokens, 42)
        XCTAssertNotNil(model.configurationResetErrorMessage)
        XCTAssertNotEqual(model.firstUseOnboardingState, .modeSelection)

        cache.clearError = nil
        let retrySucceeded = await model.resetConfiguration(disableLaunchAtLogin: {})
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(model.firstUseOnboardingState, .modeSelection)
        XCTAssertNil(model.profileState.loadedValue)
        XCTAssertNil(model.configurationResetErrorMessage)
    }

    private func makeModel(
        mode: DashboardDataMode,
        events: ModeEventRecorder,
        local: DashboardDataReading,
        cache: DashboardCacheStoring = ModeCache(),
        apiError: Error? = nil,
        statusTextEnabled: Bool = false
    ) -> DashboardViewModel {
        DashboardViewModel(
            api: ModeAPI(events: events, error: apiError),
            cli: ModeCLI(events: events),
            localDataSource: local,
            preferencesStore: ModePreferences(UserPreferences(
                username: "online-user",
                tokscaleVersion: "latest",
                npxPath: "",
                dataMode: mode,
                hasCompletedInitialization: true,
                statusTextEnabled: statusTextEnabled
            )),
            npxLocator: ModeNpxLocator(),
            cacheStore: cache
        )
    }
}

private actor ModeEventRecorder {
    private var events: [String] = []
    func add(_ event: String) { events.append(event) }
    func snapshot() -> [String] { events }
}

private enum ModeFailure: LocalizedError {
    case unavailable
    var errorDescription: String? { "unavailable" }
}

private struct ModeAPI: TokscaleAPIService {
    let events: ModeEventRecorder
    var error: Error?

    init(events: ModeEventRecorder, error: Error? = nil) {
        self.events = events
        self.error = error
    }

    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch {
        await events.add("online")
        if let error { throw error }
        return try DashboardProfileBatch(username: username, profiles: modeProfiles(tokens: 99, username: username))
    }
}

private struct ModeLocalSource: DashboardDataReading {
    let source = DashboardDataMode.local
    let events: ModeEventRecorder
    let tokens: Double
    func fetchDashboardBatch(_ request: DashboardSourceRequest) async throws -> DashboardSourceBatch {
        guard case .local = request else { throw DashboardSourceError.invalidGraph }
        await events.add("local")
        return try DashboardSourceBatch(source: .local, account: nil, profiles: modeProfiles(tokens: tokens, username: ""))
    }
}

private actor SuspendedModeLocalSource: DashboardDataReading {
    let source = DashboardDataMode.local
    let events: ModeEventRecorder
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Double, Never>?

    init(events: ModeEventRecorder) { self.events = events }

    func fetchDashboardBatch(_ request: DashboardSourceRequest) async throws -> DashboardSourceBatch {
        guard case .local = request else { throw DashboardSourceError.invalidGraph }
        await events.add("local")
        started = true
        startedWaiters.forEach { $0.resume() }
        startedWaiters.removeAll()
        let tokens = await withCheckedContinuation { continuation = $0 }
        return try DashboardSourceBatch(
            source: .local,
            account: nil,
            profiles: modeProfiles(tokens: tokens, username: "")
        )
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func resume(tokens: Double) {
        continuation?.resume(returning: tokens)
        continuation = nil
    }
}

private struct ModeCLI: TokscaleCLIService {
    let events: ModeEventRecorder
    func whoAmI(context: TokscaleCommandContext) async throws -> String { "online-user" }
    func loginCursor(context: TokscaleCommandContext) async throws {}
    func cursorStatus(context: TokscaleCommandContext) async throws -> CursorSessionStatus { .valid }
    func submit(context: TokscaleCommandContext) async throws { await events.add("submit") }
    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false,"intervalMinutes":60}"#.utf8))
    }
    func configureAutosubmit(_ configuration: AutosubmitConfiguration, context: TokscaleCommandContext) async throws {}
    func disableAutosubmit(context: TokscaleCommandContext) async throws {}
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {}
}

private struct StatusRecordingModeCLI: TokscaleCLIService {
    let events: ModeEventRecorder
    func whoAmI(context: TokscaleCommandContext) async throws -> String { "online-user" }
    func loginCursor(context: TokscaleCommandContext) async throws {}
    func cursorStatus(context: TokscaleCommandContext) async throws -> CursorSessionStatus { .valid }
    func submit(context: TokscaleCommandContext) async throws { await events.add("submit") }
    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        await events.add("status")
        return try JSONDecoder().decode(
            AutosubmitStatus.self,
            from: Data(#"{"enabled":false,"intervalMinutes":60}"#.utf8)
        )
    }
    func configureAutosubmit(_ configuration: AutosubmitConfiguration, context: TokscaleCommandContext) async throws {}
    func disableAutosubmit(context: TokscaleCommandContext) async throws {}
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {}
}

private final class ModePreferences: PreferencesStoring {
    var value: UserPreferences
    private(set) var didClear = false
    init(_ value: UserPreferences) { self.value = value }
    func load() -> UserPreferences { value }
    func save(_ preferences: UserPreferences) { value = preferences }
    func clear() throws {
        didClear = true
        value = .defaults
    }
}

private final class ModeCache: DashboardCacheStoring {
    private let snapshot: DashboardCacheSnapshot?
    private(set) var didClear = false
    var clearError: Error?

    init(snapshot: DashboardCacheSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() -> DashboardCacheSnapshot? { snapshot }
    func save(_ snapshot: DashboardCacheSnapshot) throws {}
    func clear() throws {
        if let clearError { throw clearError }
        didClear = true
    }
}

private final class RecordingModeCache: DashboardCacheStoring {
    private let snapshot: DashboardCacheSnapshot?
    private(set) var lastSaved: DashboardCacheSnapshot?

    init(snapshot: DashboardCacheSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() -> DashboardCacheSnapshot? { lastSaved ?? snapshot }
    func save(_ snapshot: DashboardCacheSnapshot) throws { lastSaved = snapshot }
    func clear() throws { lastSaved = nil }
}

private struct ModeNpxLocator: NpxLocating {
    func locate(preferredPath: String?) -> URL? { URL(fileURLWithPath: "/tmp/npx") }
}

private func modeProfiles(tokens: Double, username: String) -> [ProfilePeriod: DashboardData] {
    Dictionary(uniqueKeysWithValues: ProfilePeriod.allCases.map { period in
        (period, DashboardData(
            period: period,
            dateRange: ProfileDateRange(start: "2026-09-10", end: "2026-09-10"),
            breakdown: TokenBreakdown(input: tokens),
            username: username,
            displayName: username.isEmpty ? "本地模式" : username,
            totalTokens: tokens,
            totalCost: tokens / 100,
            updatedAt: Date(timeIntervalSince1970: 1_788_425_600),
            clients: []
        ))
    })
}
