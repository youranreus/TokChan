import XCTest
@testable import TokChan

@MainActor
final class DashboardViewModelTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_788_425_600)

    func testHydratesCompleteCachedContentBeforeRefreshing() throws {
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let viewModel = makeViewModel(cache: InMemoryCache(snapshot: snapshot), now: { self.referenceDate })

        XCTAssertEqual(viewModel.profileState.loadedValue, snapshot.profile)
        XCTAssertEqual(viewModel.cacheSavedAt, referenceDate)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testStatusTitleUsesConfiguredCachedPeriodWithoutChangingDashboardSelection() throws {
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let preferences = InMemoryPreferences(value: UserPreferences(
            username: "youranreus",
            tokscaleVersion: "latest",
            npxPath: "",
            statusTextEnabled: true,
            statusTextTemplate: "日 {token} / {cost}",
            statusTextPeriod: .day
        ))
        let viewModel = DashboardViewModel(
            api: FakeAPI(recorder: EventRecorder()),
            cli: FakeCLI(recorder: EventRecorder()),
            preferencesStore: preferences,
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: snapshot),
            now: { self.referenceDate }
        )
        let day = try XCTUnwrap(snapshot.profiles.first { $0.data.period == .day }?.data)

        XCTAssertEqual(viewModel.selectedPeriod, .all)
        XCTAssertEqual(viewModel.profileState.loadedValue?.period, .all)
        XCTAssertEqual(
            viewModel.statusItemTitle,
            StatusItemTextRenderer.render(template: "日 {token} / {cost}", data: day)
        )
    }

    func testStatusTitleRequiresEnabledNonemptyTemplateAndVerifiedCompleteAccountCache() throws {
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let disabled = DashboardViewModel(
            api: FakeAPI(recorder: EventRecorder()),
            cli: FakeCLI(recorder: EventRecorder()),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: snapshot)
        )
        XCTAssertNil(disabled.statusItemTitle)

        let emptyTemplate = DashboardViewModel(
            api: FakeAPI(recorder: EventRecorder()),
            cli: FakeCLI(recorder: EventRecorder()),
            preferencesStore: InMemoryPreferences(value: UserPreferences(
                username: "youranreus",
                tokscaleVersion: "latest",
                npxPath: "",
                statusTextEnabled: true,
                statusTextTemplate: "",
                statusTextPeriod: .day
            )),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: snapshot)
        )
        XCTAssertNil(emptyTemplate.statusItemTitle)

        let noCache = DashboardViewModel(
            api: FakeAPI(recorder: EventRecorder()),
            cli: FakeCLI(recorder: EventRecorder()),
            preferencesStore: InMemoryPreferences(value: UserPreferences(
                username: "youranreus",
                tokscaleVersion: "latest",
                npxPath: "",
                statusTextEnabled: true
            )),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )
        XCTAssertNil(noCache.statusItemTitle)

        let enabledPreferences = UserPreferences(
            username: "youranreus",
            tokscaleVersion: "latest",
            npxPath: "",
            statusTextEnabled: true
        )
        let incompleteSnapshot = DashboardCacheSnapshot(
            profile: snapshot.profile,
            autosubmit: snapshot.autosubmit,
            savedAt: referenceDate,
            profiles: Array(snapshot.profiles.dropLast()),
            username: "youranreus",
            fetchedAt: referenceDate
        )
        let incompleteCache = DashboardViewModel(
            api: FakeAPI(recorder: EventRecorder()),
            cli: FakeCLI(recorder: EventRecorder()),
            preferencesStore: InMemoryPreferences(value: enabledPreferences),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: incompleteSnapshot)
        )
        XCTAssertNil(incompleteCache.statusItemTitle)

        let unverifiedBatch = DashboardCacheSnapshot(
            profile: snapshot.profile,
            autosubmit: snapshot.autosubmit,
            savedAt: referenceDate,
            profiles: snapshot.profiles,
            username: "youranreus",
            fetchedAt: nil
        )
        let unverifiedCache = DashboardViewModel(
            api: FakeAPI(recorder: EventRecorder()),
            cli: FakeCLI(recorder: EventRecorder()),
            preferencesStore: InMemoryPreferences(value: enabledPreferences),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: unverifiedBatch)
        )
        XCTAssertNil(unverifiedCache.statusItemTitle)

        let wrongAccount = DashboardViewModel(
            api: FakeAPI(recorder: EventRecorder()),
            cli: FakeCLI(recorder: EventRecorder()),
            preferencesStore: InMemoryPreferences(value: UserPreferences(
                username: "someone-else",
                tokscaleVersion: "latest",
                npxPath: "",
                statusTextEnabled: true
            )),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: snapshot)
        )
        XCTAssertNil(wrongAccount.statusItemTitle)
    }

    func testFailedRefreshPreservesStatusTitleFromOldCompleteBatch() async throws {
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: EventRecorder(), fetchError: TestFailure.unavailable),
            cli: FakeCLI(recorder: EventRecorder()),
            preferencesStore: InMemoryPreferences(value: UserPreferences(
                username: "youranreus",
                tokscaleVersion: "latest",
                npxPath: "",
                statusTextEnabled: true
            )),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: snapshot),
            now: { self.referenceDate.addingTimeInterval(301) }
        )
        let oldTitle = model.statusItemTitle

        await model.pullStatisticsNow()

        XCTAssertNotNil(oldTitle)
        XCTAssertEqual(model.statusItemTitle, oldTitle)
        XCTAssertNotNil(model.loadErrorMessage)
    }

    func testUnresolvedIdentityDoesNotDisplayAnAccountSnapshot() throws {
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let viewModel = DashboardViewModel(
            api: FakeAPI(recorder: EventRecorder()),
            cli: FakeCLI(recorder: EventRecorder()),
            preferencesStore: InMemoryPreferences(
                value: UserPreferences(username: "", tokscaleVersion: "latest", npxPath: "")
            ),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: snapshot),
            now: { self.referenceDate }
        )

        XCTAssertNil(viewModel.profileState.loadedValue)
        XCTAssertNil(viewModel.identityProfile)
        XCTAssertNil(viewModel.cacheSavedAt)
        XCTAssertEqual(viewModel.currentAutosubmitStatus, snapshot.autosubmit)
    }

    func testFreshCompleteCacheSkipsStatisticsButRefreshesStatus() async throws {
        let recorder = EventRecorder()
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let viewModel = makeViewModel(
            recorder: recorder,
            cache: InMemoryCache(snapshot: snapshot),
            now: { self.referenceDate.addingTimeInterval(299) }
        )

        await viewModel.load()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["status"])
        XCTAssertEqual(viewModel.profileState.loadedValue, snapshot.profile)
    }

    func testTTLBoundaryTriggersOneReadOnlyBatch() async throws {
        let recorder = EventRecorder()
        let viewModel = makeViewModel(
            recorder: recorder,
            cache: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            now: { self.referenceDate.addingTimeInterval(300) }
        )

        await viewModel.load()

        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "fetch" }.count, 1)
        XCTAssertEqual(events.filter { $0 == "status" }.count, 1)
        XCTAssertFalse(events.contains("submit"))
    }

    func testFailedBatchKeepsEveryCachedRangeAndFetchedTime() async throws {
        let recorder = EventRecorder()
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let model = makeViewModel(
            recorder: recorder,
            api: FakeAPI(recorder: recorder, fetchError: TestFailure.unavailable),
            cache: InMemoryCache(snapshot: snapshot),
            now: { self.referenceDate.addingTimeInterval(301) }
        )

        await model.load()
        for period in ProfilePeriod.allCases {
            await model.selectPeriod(period)
            XCTAssertEqual(model.profileState.loadedValue?.period, period)
        }
        XCTAssertEqual(model.cacheSavedAt, referenceDate)
        XCTAssertNotNil(model.loadErrorMessage)
    }

    func testInitialLoadReadsOnlyBatchAndAutosubmitStatus() async {
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder)

        await model.load()

        let events = await recorder.snapshot()
        XCTAssertEqual(Set(events), Set(["fetch", "status"]))
        XCTAssertEqual(model.profileState.loadedValue?.period, .all)
        XCTAssertNotNil(model.currentAutosubmitStatus)
    }

    func testManualRefreshSubmitsBeforeFetchingAllRanges() async {
        let recorder = EventRecorder()
        let cache = InMemoryCache()
        let model = makeViewModel(recorder: recorder, cache: cache)

        await model.refresh()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit", "fetch"])
        XCTAssertEqual(Set(cache.snapshot?.profiles.map(\.data.period) ?? []), Set(ProfilePeriod.allCases))
        XCTAssertNotNil(cache.snapshot?.fetchedAt)
        XCTAssertEqual(model.operation, .succeeded("用量已提交，全部范围已更新。"))
    }

    func testPushOnlySubmitsExactlyOnceWithoutFetchingOrReadingStatus() async {
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder)

        await model.pushUsageNow()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit"])
        XCTAssertEqual(model.operation, .idle)
        XCTAssertNil(model.pushErrorMessage)
    }

    func testPullOnlyFetchesExactlyOneCompleteBatchWithoutSubmitting() async {
        let recorder = EventRecorder()
        let cache = InMemoryCache()
        let model = makeViewModel(recorder: recorder, cache: cache)

        await model.pullStatisticsNow()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["fetch"])
        XCTAssertEqual(Set(cache.snapshot?.profiles.map(\.data.period) ?? []), Set(ProfilePeriod.allCases))
        XCTAssertEqual(model.operation, .idle)
    }

    func testImmediateActionFailuresAppearInDiagnostics() async {
        let pushRecorder = EventRecorder()
        let pushModel = DashboardViewModel(
            api: FakeAPI(recorder: pushRecorder),
            cli: FakeCLI(recorder: pushRecorder, submitError: TestFailure.unavailable),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        await pushModel.pushUsageNow()

        let pushEvents = await pushRecorder.snapshot()
        XCTAssertEqual(pushEvents, ["submit"])
        XCTAssertNotNil(pushModel.pushErrorMessage)
        XCTAssertTrue(pushModel.diagnosticMessages.contains { $0.hasPrefix("即时推送：") })

        let pullRecorder = EventRecorder()
        let pullModel = makeViewModel(
            recorder: pullRecorder,
            api: FakeAPI(recorder: pullRecorder, fetchError: TestFailure.unavailable)
        )

        await pullModel.pullStatisticsNow()

        let pullEvents = await pullRecorder.snapshot()
        XCTAssertEqual(pullEvents, ["fetch"])
        XCTAssertNotNil(pullModel.loadErrorMessage)
        XCTAssertTrue(pullModel.diagnosticMessages.contains { $0.hasPrefix("统计读取：") })
    }

    func testRunningImmediatePushRejectsPullAndDuplicatePush() async {
        let recorder = EventRecorder()
        let cli = SuspendedPushCLI(recorder: recorder)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: cli,
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        let firstPush = Task { await model.pushUsageNow() }
        await cli.waitForSubmit()
        XCTAssertEqual(model.operation, .pushing)

        await model.pullStatisticsNow()
        await model.pushUsageNow()
        var events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit"])

        await cli.resumeSubmit()
        await firstPush.value
        events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit"])
        XCTAssertEqual(model.operation, .idle)
    }

    func testSubmitFailureStopsStatisticsRead() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, submitError: TestFailure.unavailable),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        await model.refresh()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit"])
        guard case .failed = model.operation else { return XCTFail("Expected failed operation") }
    }

    func testRunNowCompletesBeforeRefreshingStatisticsAndStatus() async {
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder)

        await model.runAutosubmitNow()

        let events = await recorder.snapshot()
        XCTAssertEqual(events.first, "run")
        XCTAssertEqual(Set(events.dropFirst()), Set(["fetch", "status"]))
        XCTAssertEqual(model.profileState.loadedValue?.period, .all)
        XCTAssertNotNil(model.currentAutosubmitStatus)
        XCTAssertEqual(model.operation, .succeeded("自动提交已完成。"))
    }

    func testSavingSettingsConfiguresBeforeRefreshingTheWholeBatch() async throws {
        let recorder = EventRecorder()
        let preferences = standardPreferences()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: preferences,
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )
        let updated = UserPreferences(
            username: "youranreus",
            tokscaleVersion: "4.15.0",
            npxPath: "/custom/npx",
            statusTextEnabled: true,
            statusTextTemplate: "月度 {token} / {cost}",
            statusTextPeriod: .month
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

        let saved = await model.saveSettings(preferences: updated, autosubmit: configuration)

        XCTAssertTrue(saved)
        let events = await recorder.snapshot()
        XCTAssertEqual(events.first, "configure")
        XCTAssertEqual(Set(events.dropFirst()), Set(["fetch", "status"]))
        XCTAssertEqual(preferences.value, updated)
        let profile = try XCTUnwrap(model.profileState.loadedValue)
        XCTAssertEqual(
            model.statusItemTitle,
            StatusItemTextRenderer.render(template: updated.statusTextTemplate, data: profile)
        )
    }

    func testStatusFailureDoesNotBlockSuccessfulStatisticsBatch() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, statusError: TestFailure.unavailable),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        await model.load()

        XCTAssertEqual(model.profileState.loadedValue?.period, .all)
        XCTAssertNotNil(model.autosubmitLoadErrorMessage)
        XCTAssertNil(model.loadErrorMessage)
    }

    func testStatusFailureKeepsPreviouslyObservedStatus() async throws {
        let recorder = EventRecorder()
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, statusError: TestFailure.unavailable),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: snapshot),
            now: { self.referenceDate.addingTimeInterval(1) }
        )

        await model.load()

        XCTAssertEqual(model.currentAutosubmitStatus, snapshot.autosubmit)
        XCTAssertEqual(model.autosubmitObservedAt, snapshot.autosubmitObservedAt)
        XCTAssertNotNil(model.autosubmitLoadErrorMessage)
    }

    func testInitialStatisticsFailureShowsARealFailureState() async {
        let recorder = EventRecorder()
        let model = makeViewModel(
            recorder: recorder,
            api: FakeAPI(recorder: recorder, fetchError: TestFailure.unavailable)
        )

        await model.load()

        XCTAssertNil(model.profileState.loadedValue)
        guard case .failed = model.profileState else {
            return XCTFail("A first load without cached data must expose a failure state")
        }
        XCTAssertNotNil(model.loadErrorMessage)
    }

    func testManualStatisticsRetryBypassesAutomaticFailureCooldownWithoutSubmitting() async {
        let recorder = EventRecorder()
        let model = makeViewModel(
            recorder: recorder,
            api: FakeAPI(recorder: recorder, fetchError: TestFailure.unavailable)
        )

        await model.load()
        await model.retryStatistics()

        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "fetch" }.count, 2)
        XCTAssertFalse(events.contains("submit"))
    }

    func testRangeSwitchUsesSameBatchWithoutAdditionalRead() async {
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder)
        await model.load()

        for period in ProfilePeriod.allCases {
            await model.selectPeriod(period)
            XCTAssertEqual(model.profileState.loadedValue?.period, period)
        }

        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "fetch" }.count, 1)
    }

    func testConcurrentLoadsAreCoalescedIntoOneBatch() async {
        let api = ControlledBatchAPI()
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder, api: api)

        let first = Task { await model.load() }
        await api.waitForRequest(username: "youranreus")
        let second = Task { await model.load() }
        await api.resolve(username: "youranreus")
        await first.value
        await second.value

        let count = await api.requestCount()
        XCTAssertEqual(count, 1)
    }

    func testManualMutationNeverReusesAPreMutationBatch() async {
        let api = QueuedBatchAPI()
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder, api: api)

        let load = Task { await model.load() }
        await waitForRequestCount(1, api: api)
        let refresh = Task { await model.refresh() }
        await waitForRequestCount(2, api: api)

        var requestCount = await api.requestCount()
        if requestCount < 2 {
            await api.resolveNext()
            await load.value
            await refresh.value
            return XCTFail("The post-submit refresh reused a pre-submit batch")
        }

        await api.resolveNext()
        await load.value
        XCTAssertNil(model.profileState.loadedValue)

        await api.resolveNext()
        await refresh.value
        requestCount = await api.requestCount()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(model.profileState.loadedValue?.period, .all)
        XCTAssertEqual(model.operation, .succeeded("用量已提交，全部范围已更新。"))
    }

    func testOldAccountBatchCannotOverwriteNewSettingsBatch() async throws {
        let api = ControlledBatchAPI()
        let recorder = EventRecorder()
        let preferences = InMemoryPreferences(
            value: UserPreferences(username: "old", tokscaleVersion: "latest", npxPath: "")
        )
        let model = DashboardViewModel(api: api, cli: FakeCLI(recorder: recorder),
            preferencesStore: preferences, npxLocator: FakeNpxLocator(), cacheStore: InMemoryCache())

        let load = Task { await model.load() }
        await api.waitForRequest(username: "old")
        let save = Task {
            await model.saveSettings(
                preferences: UserPreferences(username: "new", tokscaleVersion: "latest", npxPath: ""),
                autosubmit: AutosubmitConfiguration(enabled: false, intervalMinutes: 120, clients: [],
                    filterKind: .all, year: "", since: "", until: "")
            )
        }
        await api.waitForRequest(username: "new")
        await api.resolve(username: "new")
        let saved = await save.value
        XCTAssertTrue(saved)
        await api.resolve(username: "old")
        await load.value

        XCTAssertEqual(model.profileState.loadedValue?.username, "new")
        XCTAssertEqual(model.preferences.username, "new")
    }

    func testCacheWriteFailureDoesNotDiscardSuccessfulMemoryBatch() async {
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder, cache: InMemoryCache(saveError: TestFailure.unavailable))

        await model.load()

        XCTAssertEqual(model.profileState.loadedValue?.period, .all)
        XCTAssertNotNil(model.cacheWriteErrorMessage)
    }

    func testAutomaticFailureCooldownSuppressesImmediateRetry() async throws {
        let recorder = EventRecorder()
        let clock = TestClock(referenceDate.addingTimeInterval(301))
        let model = makeViewModel(
            recorder: recorder,
            api: FakeAPI(recorder: recorder, fetchError: TestFailure.unavailable),
            cache: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            now: { clock.value }
        )

        await model.load()
        await model.load()
        var fetchCount = await recorder.snapshot().filter { $0 == "fetch" }.count
        XCTAssertEqual(fetchCount, 1)

        clock.value.addTimeInterval(30)
        await model.load()
        fetchCount = await recorder.snapshot().filter { $0 == "fetch" }.count
        XCTAssertEqual(fetchCount, 2)
    }

    func testVisibleTimerRefreshesAndStopsAfterPanelDisappears() async {
        let recorder = EventRecorder()
        let clock = TestClock(referenceDate)
        let sleeper = ManualSleeper()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(),
            now: { clock.value },
            refreshInterval: 300,
            retryInterval: 0,
            sleep: { await sleeper.sleep($0) }
        )
        await model.load()

        model.panelDidAppear()
        await sleeper.waitUntilSleeping()
        clock.value.addTimeInterval(300)
        await sleeper.advance()
        await waitForFetchCount(2, recorder: recorder)
        var fetchCount = await recorder.snapshot().filter { $0 == "fetch" }.count
        XCTAssertEqual(fetchCount, 2)

        await sleeper.waitUntilSleeping()
        model.panelDidDisappear()
        clock.value.addTimeInterval(300)
        await sleeper.advance()
        for _ in 0..<10 { await Task.yield() }
        fetchCount = await recorder.snapshot().filter { $0 == "fetch" }.count
        XCTAssertEqual(fetchCount, 2)
    }

    func testVisibleTimerUsesTheRemainingFreshnessWindow() async throws {
        let clock = TestClock(referenceDate.addingTimeInterval(240))
        let sleeper = ManualSleeper()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: EventRecorder()),
            cli: FakeCLI(recorder: EventRecorder()),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            now: { clock.value },
            refreshInterval: 300,
            sleep: { await sleeper.sleep($0) }
        )

        model.panelDidAppear()
        await sleeper.waitUntilSleeping()

        let requestedNanoseconds = await sleeper.requestedNanoseconds()
        XCTAssertEqual(requestedNanoseconds, 60_000_000_000)
        model.panelDidDisappear()
        await sleeper.advance()
    }

    func testVisibleTimerSleepsForFailureCooldownAfterAStaleRefreshFails() async throws {
        let recorder = EventRecorder()
        let clock = TestClock(referenceDate.addingTimeInterval(301))
        let sleeper = ManualSleeper()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder, fetchError: TestFailure.unavailable),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            now: { clock.value },
            refreshInterval: 300,
            retryInterval: 30,
            sleep: { await sleeper.sleep($0) }
        )

        model.panelDidAppear()
        await sleeper.waitUntilSleeping()

        let requestedNanoseconds = await sleeper.requestedNanoseconds()
        XCTAssertEqual(requestedNanoseconds, 30_000_000_000)
        model.panelDidDisappear()
        await sleeper.advance()
    }

    private func waitForFetchCount(_ expected: Int, recorder: EventRecorder) async {
        for _ in 0..<100 {
            if await recorder.snapshot().filter({ $0 == "fetch" }).count >= expected { return }
            await Task.yield()
        }
    }

    private func waitForRequestCount(_ expected: Int, api: QueuedBatchAPI) async {
        for _ in 0..<100 {
            if await api.requestCount() >= expected { return }
            await Task.yield()
        }
    }

    private func makeViewModel(
        recorder: EventRecorder = EventRecorder(),
        api: TokscaleAPIService? = nil,
        cache: InMemoryCache = InMemoryCache(),
        now: @escaping () -> Date = Date.init
    ) -> DashboardViewModel {
        DashboardViewModel(
            api: api ?? FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: cache,
            now: now
        )
    }

    private func standardPreferences() -> InMemoryPreferences {
        InMemoryPreferences(
            value: UserPreferences(username: "youranreus", tokscaleVersion: "latest", npxPath: "")
        )
    }

    private func completeSnapshot(fetchedAt: Date) throws -> DashboardCacheSnapshot {
        let batch = try makeBatch(username: "youranreus")
        let profiles = ProfilePeriod.allCases.compactMap { period in
            batch.profiles[period].map { CachedDashboardProfile(data: $0, savedAt: fetchedAt) }
        }
        return DashboardCacheSnapshot(
            profile: batch.profiles[.all],
            autosubmit: try makeAutosubmitStatus(),
            savedAt: fetchedAt,
            profiles: profiles,
            username: "youranreus",
            fetchedAt: fetchedAt,
            autosubmitObservedAt: fetchedAt
        )
    }

    private func makeAutosubmitStatus() throws -> AutosubmitStatus {
        try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":true,"intervalMinutes":120}"#.utf8))
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

    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch {
        await recorder.append("fetch")
        if let fetchError { throw fetchError }
        return try makeBatch(username: username)
    }
}

private func makeBatch(username: String) throws -> DashboardProfileBatch {
    var profiles: [ProfilePeriod: DashboardData] = [:]
    for period in ProfilePeriod.allCases {
        let response = try JSONDecoder().decode(
            PublicProfileResponse.self,
            from: try scopedFixture(period: period, username: username)
        )
        profiles[period] = DashboardData(response: response)
    }
    return try DashboardProfileBatch(username: username, profiles: profiles)
}

private func scopedFixture(period: ProfilePeriod, username: String) throws -> Data {
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ProfileModelsTests.profileJSON.utf8)) as? [String: Any])
    json["period"] = period.rawValue
    var user = try XCTUnwrap(json["user"] as? [String: Any])
    user["username"] = username
    json["user"] = user
    return try JSONSerialization.data(withJSONObject: json)
}

private final class FakeCLI: TokscaleCLIService {
    let recorder: EventRecorder
    let submitError: Error?
    let statusError: Error?

    init(recorder: EventRecorder, submitError: Error? = nil, statusError: Error? = nil) {
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
        return try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false}"#.utf8))
    }
    func configureAutosubmit(_ configuration: AutosubmitConfiguration, context: TokscaleCommandContext) async throws {
        await recorder.append("configure")
    }
    func disableAutosubmit(context: TokscaleCommandContext) async throws { await recorder.append("disable") }
    func runAutosubmitNow(context: TokscaleCommandContext) async throws { await recorder.append("run") }
}

private actor SuspendedPushCLI: TokscaleCLIService {
    private let recorder: EventRecorder
    private var submitContinuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var submitStarted = false

    init(recorder: EventRecorder) {
        self.recorder = recorder
    }

    func whoAmI(context: TokscaleCommandContext) async throws -> String { "youranreus" }

    func submit(context: TokscaleCommandContext) async throws {
        await recorder.append("submit")
        submitStarted = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        await withCheckedContinuation { submitContinuation = $0 }
    }

    func waitForSubmit() async {
        if submitStarted { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func resumeSubmit() {
        submitContinuation?.resume()
        submitContinuation = nil
    }

    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false}"#.utf8))
    }
    func configureAutosubmit(
        _ configuration: AutosubmitConfiguration,
        context: TokscaleCommandContext
    ) async throws {}
    func disableAutosubmit(context: TokscaleCommandContext) async throws {}
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {}
}

private enum TestFailure: Error { case unavailable }

@MainActor
private final class TestClock {
    var value: Date
    init(_ value: Date) { self.value = value }
}

private actor ManualSleeper {
    private var sleepContinuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var latestNanoseconds: UInt64?

    func sleep(_ nanoseconds: UInt64) async {
        await withCheckedContinuation { continuation in
            latestNanoseconds = nanoseconds
            sleepContinuation = continuation
            arrivalContinuation?.resume()
            arrivalContinuation = nil
        }
    }

    func waitUntilSleeping() async {
        if sleepContinuation != nil { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func advance() {
        sleepContinuation?.resume()
        sleepContinuation = nil
    }

    func requestedNanoseconds() -> UInt64? { latestNanoseconds }
}

private final class InMemoryPreferences: PreferencesStoring {
    var value: UserPreferences
    init(value: UserPreferences) { self.value = value }
    func load() -> UserPreferences { value }
    func save(_ preferences: UserPreferences) { value = preferences }
}

private struct FakeNpxLocator: NpxLocating {
    func locate(preferredPath: String?) -> URL? { URL(fileURLWithPath: "/usr/bin/npx") }
}

private final class InMemoryCache: DashboardCacheStoring {
    var snapshot: DashboardCacheSnapshot?
    let saveError: Error?

    init(snapshot: DashboardCacheSnapshot? = nil, saveError: Error? = nil) {
        self.snapshot = snapshot
        self.saveError = saveError
    }
    func load() -> DashboardCacheSnapshot? { snapshot }
    func save(_ snapshot: DashboardCacheSnapshot) throws {
        if let saveError { throw saveError }
        self.snapshot = snapshot
    }
}

private actor ControlledBatchAPI: TokscaleAPIService {
    private var pending: [String: CheckedContinuation<DashboardProfileBatch, Error>] = [:]
    private var arrivals: [String: CheckedContinuation<Void, Never>] = [:]
    private var count = 0

    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch {
        count += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[username] = continuation
            arrivals.removeValue(forKey: username)?.resume()
        }
    }

    func waitForRequest(username: String) async {
        if pending[username] != nil { return }
        await withCheckedContinuation { arrivals[username] = $0 }
    }

    func resolve(username: String) {
        do { pending.removeValue(forKey: username)?.resume(returning: try makeBatch(username: username)) }
        catch { pending.removeValue(forKey: username)?.resume(throwing: error) }
    }

    func requestCount() -> Int { count }
}

private actor QueuedBatchAPI: TokscaleAPIService {
    private var pending: [(String, CheckedContinuation<DashboardProfileBatch, Error>)] = []
    private var count = 0

    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch {
        count += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending.append((username, continuation))
        }
    }

    func requestCount() -> Int { count }

    func resolveNext() {
        guard !pending.isEmpty else { return }
        let (username, continuation) = pending.removeFirst()
        do { continuation.resume(returning: try makeBatch(username: username)) }
        catch { continuation.resume(throwing: error) }
    }
}
