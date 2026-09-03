import XCTest
@testable import TokChan

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testHydratesCachedContentBeforeRefreshing() throws {
        let cachedProfile = try makeDashboardData()
        let cachedStatus = try makeAutosubmitStatus()
        let cache = InMemoryCache(
            snapshot: DashboardCacheSnapshot(
                profile: cachedProfile,
                autosubmit: cachedStatus,
                savedAt: Date(timeIntervalSince1970: 1_788_425_600)
            )
        )
        let viewModel = DashboardViewModel(
            api: FakeAPI(recorder: EventRecorder()),
            cli: FakeCLI(recorder: EventRecorder()),
            preferencesStore: InMemoryPreferences(
                value: UserPreferences(username: "youranreus", tokscaleVersion: "latest", npxPath: "")
            ),
            npxLocator: FakeNpxLocator(),
            cacheStore: cache
        )

        guard case let .loaded(profile) = viewModel.profileState,
              case let .loaded(status) = viewModel.autosubmitState else {
            return XCTFail("Expected cached content to be visible immediately")
        }
        XCTAssertEqual(profile, cachedProfile)
        XCTAssertEqual(status, cachedStatus)
        XCTAssertNotNil(viewModel.cacheSavedAt)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testSuccessfulLoadPersistsProfileAndAutosubmitSnapshot() async {
        let recorder = EventRecorder()
        let cache = InMemoryCache()
        let viewModel = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: InMemoryPreferences(
                value: UserPreferences(username: "youranreus", tokscaleVersion: "latest", npxPath: "")
            ),
            npxLocator: FakeNpxLocator(),
            cacheStore: cache
        )

        await viewModel.load()

        XCTAssertNotNil(cache.snapshot?.profile)
        XCTAssertNotNil(cache.snapshot?.autosubmit)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testRefreshFailureKeepsCachedContentVisible() async throws {
        let cachedProfile = try makeDashboardData()
        let cachedStatus = try makeAutosubmitStatus()
        let cache = InMemoryCache(
            snapshot: DashboardCacheSnapshot(
                profile: cachedProfile,
                autosubmit: cachedStatus,
                savedAt: Date(timeIntervalSince1970: 1_788_425_600)
            )
        )
        let recorder = EventRecorder()
        let viewModel = DashboardViewModel(
            api: FakeAPI(recorder: recorder, fetchError: TestFailure.unavailable),
            cli: FakeCLI(recorder: recorder, statusError: TestFailure.unavailable),
            preferencesStore: InMemoryPreferences(
                value: UserPreferences(username: "youranreus", tokscaleVersion: "latest", npxPath: "")
            ),
            npxLocator: FakeNpxLocator(),
            cacheStore: cache
        )

        await viewModel.load()

        guard case let .loaded(profile) = viewModel.profileState,
              case let .loaded(status) = viewModel.autosubmitState else {
            return XCTFail("Expected stale cache to remain visible")
        }
        XCTAssertEqual(profile, cachedProfile)
        XCTAssertEqual(status, cachedStatus)
        XCTAssertNotNil(viewModel.loadErrorMessage)
    }

    func testInitialLoadOnlyReadsProfileAndAutosubmitStatus() async {
        let recorder = EventRecorder()
        let viewModel = makeViewModel(recorder: recorder)

        await viewModel.load()

        let events = await recorder.snapshot()
        XCTAssertEqual(Set(events), Set(["fetch", "status"]))
        XCTAssertFalse(events.contains("submit"))
        guard case .loaded = viewModel.profileState,
              case .loaded = viewModel.autosubmitState else {
            return XCTFail("Expected both read-only resources to load")
        }
    }

    func testManualRefreshSubmitsBeforeFetchingProfile() async throws {
        let recorder = EventRecorder()
        let cli = FakeCLI(recorder: recorder)
        let api = FakeAPI(recorder: recorder)
        let preferences = InMemoryPreferences(
            value: UserPreferences(username: "youranreus", tokscaleVersion: "4.15.0", npxPath: "")
        )
        let viewModel = DashboardViewModel(
            api: api,
            cli: cli,
            preferencesStore: preferences,
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        await viewModel.refresh()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit", "fetch"])
        guard case .loaded = viewModel.profileState else {
            return XCTFail("Expected a loaded profile")
        }
    }

    func testSubmitFailureStopsProfileFetch() async {
        let recorder = EventRecorder()
        let cli = FakeCLI(recorder: recorder, submitError: TokscaleCLIError.failed(exitCode: 1, message: "failed"))
        let viewModel = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: cli,
            preferencesStore: InMemoryPreferences(
                value: UserPreferences(username: "youranreus", tokscaleVersion: "latest", npxPath: "")
            ),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        await viewModel.refresh()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit"])
        guard case .failed = viewModel.operation else {
            return XCTFail("Expected a failed operation")
        }
    }

    func testRunNowReloadsStatusAndProfileAfterCLICompletes() async {
        let recorder = EventRecorder()
        let viewModel = makeViewModel(recorder: recorder)

        await viewModel.runAutosubmitNow()

        let events = await recorder.snapshot()
        XCTAssertEqual(events.first, "run")
        XCTAssertEqual(Set(events.dropFirst()), Set(["status", "fetch"]))
        guard case .loaded = viewModel.profileState,
              case .loaded = viewModel.autosubmitState else {
            return XCTFail("Expected run-now to reload profile and status")
        }
    }

    func testSavingEnabledAutosubmitAppliesConfigurationBeforeReloading() async {
        let recorder = EventRecorder()
        let preferences = InMemoryPreferences(
            value: UserPreferences(username: "old", tokscaleVersion: "latest", npxPath: "")
        )
        let viewModel = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: preferences,
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )
        let updated = UserPreferences(
            username: "youranreus",
            tokscaleVersion: "4.15.0",
            npxPath: "/custom/npx"
        )
        let configuration = AutosubmitConfiguration(
            enabled: true,
            intervalMinutes: 120,
            clients: ["codex"],
            filterKind: .week,
            year: "",
            since: "",
            until: ""
        )

        let saved = await viewModel.saveSettings(preferences: updated, autosubmit: configuration)

        XCTAssertTrue(saved)
        let events = await recorder.snapshot()
        XCTAssertEqual(events.first, "configure")
        XCTAssertEqual(Set(events.dropFirst()), Set(["status", "fetch"]))
        XCTAssertEqual(preferences.value, updated)
    }

    private func makeViewModel(recorder: EventRecorder) -> DashboardViewModel {
        DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: InMemoryPreferences(
                value: UserPreferences(username: "youranreus", tokscaleVersion: "latest", npxPath: "")
            ),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )
    }

    private func makeDashboardData() throws -> DashboardData {
        let response = try JSONDecoder().decode(
            PublicProfileResponse.self,
            from: Data(ProfileModelsTests.profileJSON.utf8)
        )
        return DashboardData(response: response)
    }

    private func makeAutosubmitStatus() throws -> AutosubmitStatus {
        try JSONDecoder().decode(
            AutosubmitStatus.self,
            from: Data(#"{"enabled":true,"intervalMinutes":120}"#.utf8)
        )
    }
}

private actor EventRecorder {
    private var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
}

private final class FakeAPI: TokscaleAPIService {
    let recorder: EventRecorder
    let fetchError: Error?

    init(recorder: EventRecorder, fetchError: Error? = nil) {
        self.recorder = recorder
        self.fetchError = fetchError
    }

    func fetchProfile(username: String) async throws -> DashboardData {
        await recorder.append("fetch")
        if let fetchError { throw fetchError }
        let response = try JSONDecoder().decode(
            PublicProfileResponse.self,
            from: Data(ProfileModelsTests.profileJSON.utf8)
        )
        return DashboardData(response: response)
    }
}

private final class FakeCLI: TokscaleCLIService {
    let recorder: EventRecorder
    let submitError: Error?
    let statusError: Error?

    init(
        recorder: EventRecorder,
        submitError: Error? = nil,
        statusError: Error? = nil
    ) {
        self.recorder = recorder
        self.submitError = submitError
        self.statusError = statusError
    }

    func whoAmI(context: TokscaleCommandContext) async throws -> String { "youranreus" }

    func submit(context: TokscaleCommandContext) async throws {
        await recorder.append("submit")
        if let submitError { throw submitError }
    }

    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        await recorder.append("status")
        if let statusError { throw statusError }
        return try JSONDecoder().decode(
            AutosubmitStatus.self,
            from: Data(#"{"enabled":false}"#.utf8)
        )
    }

    func configureAutosubmit(
        _ configuration: AutosubmitConfiguration,
        context: TokscaleCommandContext
    ) async throws {
        await recorder.append("configure")
    }

    func disableAutosubmit(context: TokscaleCommandContext) async throws {
        await recorder.append("disable")
    }

    func runAutosubmitNow(context: TokscaleCommandContext) async throws {
        await recorder.append("run")
    }
}

private enum TestFailure: Error {
    case unavailable
}

private final class InMemoryPreferences: PreferencesStoring {
    var value: UserPreferences
    init(value: UserPreferences) { self.value = value }
    func load() -> UserPreferences { value }
    func save(_ preferences: UserPreferences) { value = preferences }
}

private struct FakeNpxLocator: NpxLocating {
    func locate(preferredPath: String?) -> URL? {
        URL(fileURLWithPath: "/usr/bin/npx")
    }
}

private final class InMemoryCache: DashboardCacheStoring {
    var snapshot: DashboardCacheSnapshot?

    init(snapshot: DashboardCacheSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() -> DashboardCacheSnapshot? { snapshot }
    func save(_ snapshot: DashboardCacheSnapshot) throws { self.snapshot = snapshot }
}
