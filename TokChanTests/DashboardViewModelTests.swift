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

    func testAutomaticIdentityDiscoveryPersistsUsernameAndVerifiesUsage() async {
        let recorder = EventRecorder()
        let preferences = InMemoryPreferences(
            value: UserPreferences(username: "", tokscaleVersion: "latest", npxPath: "")
        )
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, discoveredUsername: "  youranreus  "),
            preferencesStore: preferences,
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        XCTAssertEqual(model.firstUseOnboardingState, .discoveringIdentity)

        await model.load()

        XCTAssertEqual(preferences.value.username, "youranreus")
        XCTAssertEqual(model.firstUseOnboardingState, .hidden)
        let events = await recorder.snapshot()
        XCTAssertEqual(events.first, "whoami")
        XCTAssertEqual(events.filter { $0 == "fetch" }.count, 1)
        XCTAssertEqual(events.filter { $0 == "status" }.count, 1)
    }

    func testAutomaticIdentityFailureFallsBackToUsernameEntryWithoutStatisticsRetryDeadEnd() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, whoAmIError: TestFailure.unavailable),
            preferencesStore: InMemoryPreferences(
                value: UserPreferences(username: "", tokscaleVersion: "latest", npxPath: "")
            ),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        await model.load()

        guard case let .usernameEntry(message) = model.firstUseOnboardingState else {
            return XCTFail("Identity discovery failure must allow manual username entry")
        }
        XCTAssertNotNil(message)
        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "whoami" }.count, 1)
        XCTAssertFalse(events.contains("fetch"))
    }

    func testManualUsernameIsTrimmedPersistedAndForceVerifiedOnce() async {
        let api = ControlledBatchAPI()
        let recorder = EventRecorder()
        let preferences = InMemoryPreferences(
            value: UserPreferences(username: "", tokscaleVersion: "latest", npxPath: "")
        )
        let model = DashboardViewModel(
            api: api,
            cli: FakeCLI(recorder: recorder),
            preferencesStore: preferences,
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        XCTAssertFalse(model.isPerformingOperation)
        let verification = Task { await model.saveAndVerifyUsername("  youranreus  ") }
        await api.waitForRequest(username: "youranreus")
        XCTAssertEqual(model.firstUseOnboardingState, .verifying(username: "youranreus"))
        XCTAssertTrue(model.isPerformingOperation)

        await model.saveAndVerifyUsername("youranreus")
        let requestCount = await api.requestCount()
        XCTAssertEqual(requestCount, 1)

        await api.resolve(username: "youranreus")
        await verification.value

        XCTAssertEqual(preferences.value.username, "youranreus")
        XCTAssertEqual(model.firstUseOnboardingState, .hidden)
        XCTAssertFalse(model.isPerformingOperation)
    }

    func testBlankManualUsernameCannotContinueOrPersist() async {
        let recorder = EventRecorder()
        let preferences = InMemoryPreferences(
            value: UserPreferences(username: "", tokscaleVersion: "latest", npxPath: "")
        )
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: preferences,
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        await model.saveAndVerifyUsername(" \n ")

        XCTAssertEqual(preferences.value.username, "")
        guard case let .usernameEntry(message) = model.firstUseOnboardingState else {
            return XCTFail("Blank input must remain on username entry")
        }
        XCTAssertNotNil(message)
        let events = await recorder.snapshot()
        XCTAssertTrue(events.isEmpty)
    }

    func testPositiveAllTokensHideOnboardingEvenWithoutClientDetails() async {
        let recorder = EventRecorder()
        let model = makeViewModel(
            recorder: recorder,
            api: FakeAPI(recorder: recorder, includesClients: false)
        )

        await model.load()

        XCTAssertEqual(model.firstUseOnboardingState, .hidden)
        XCTAssertTrue(model.profileState.loadedValue?.clients.isEmpty == true)
        XCTAssertTrue((model.profileState.loadedValue?.totalTokens ?? 0) > 0)
    }

    func testZeroUsageAndProfileNotFoundBothAdvanceToFirstSubmission() async {
        let zeroRecorder = EventRecorder()
        let zeroModel = makeViewModel(
            recorder: zeroRecorder,
            api: FakeAPI(recorder: zeroRecorder, totalTokens: 0)
        )

        await zeroModel.load()

        XCTAssertEqual(
            zeroModel.firstUseOnboardingState,
            .firstSubmission(username: "youranreus", message: nil)
        )

        let missingRecorder = EventRecorder()
        let missingModel = makeViewModel(
            recorder: missingRecorder,
            api: FakeAPI(recorder: missingRecorder, fetchError: TokscaleAPIError.profileNotFound)
        )

        await missingModel.load()

        XCTAssertEqual(
            missingModel.firstUseOnboardingState,
            .firstSubmission(username: "youranreus", message: nil)
        )
    }

    func testOtherInitialVerificationFailureReturnsToPrefilledUsernameEntry() async {
        let recorder = EventRecorder()
        let model = makeViewModel(
            recorder: recorder,
            api: FakeAPI(recorder: recorder, fetchError: TestFailure.unavailable)
        )

        await model.load()

        guard case let .usernameEntry(message) = model.firstUseOnboardingState else {
            return XCTFail("A retryable verification error must return to username entry")
        }
        XCTAssertNotNil(message)
        XCTAssertEqual(model.preferences.username, "youranreus")
    }

    func testSuccessfulZeroUsageRetryLeavesVerificationErrorForFirstSubmission() async {
        let api = ControlledBatchAPI()
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder, api: api)

        let initialLoad = Task { await model.load() }
        await api.waitForRequest(username: "youranreus")
        await api.reject(username: "youranreus")
        await initialLoad.value
        guard case .usernameEntry(message: .some) = model.firstUseOnboardingState else {
            return XCTFail("Expected a retryable username verification error")
        }

        let retry = Task { await model.retryStatistics() }
        await api.waitForRequest(username: "youranreus")
        await api.resolve(username: "youranreus", totalTokens: 0)
        await retry.value

        XCTAssertEqual(
            model.firstUseOnboardingState,
            .firstSubmission(username: "youranreus", message: nil)
        )
    }

    func testFirstSubmissionSubmitsThenFetchesAndHidesOnPositiveUsage() async {
        let recorder = EventRecorder()
        let api = SequencedBatchAPI(recorder: recorder, totalTokens: [0, nil])
        let model = makeViewModel(recorder: recorder, api: api)
        await model.load()
        await recorder.reset()

        await model.submitFirstUsage()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit", "fetch"])
        XCTAssertEqual(model.firstUseOnboardingState, .hidden)
    }

    func testFirstSubmissionRejectsDuplicateActionWhileSubmitIsRunning() async throws {
        let recorder = EventRecorder()
        let cli = SuspendedPushCLI(recorder: recorder)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: cli,
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: try completeSnapshot(
                fetchedAt: referenceDate,
                totalTokens: 0
            )),
            now: { self.referenceDate }
        )

        let submission = Task { await model.submitFirstUsage() }
        await cli.waitForSubmit()
        XCTAssertEqual(model.firstUseOnboardingState, .submitting(username: "youranreus"))

        await model.submitFirstUsage()
        var events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit"])

        await cli.resumeSubmit()
        await submission.value
        events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit", "fetch"])
        XCTAssertEqual(model.firstUseOnboardingState, .hidden)
    }

    func testUsernameChangeDuringFirstSubmissionDoesNotFetchForTheNewAccount() async throws {
        let recorder = EventRecorder()
        let cli = SuspendedPushCLI(recorder: recorder)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: cli,
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: try completeSnapshot(
                fetchedAt: referenceDate,
                totalTokens: 0
            )),
            now: { self.referenceDate }
        )

        let submission = Task { await model.submitFirstUsage() }
        await cli.waitForSubmit()
        model.updatePreferences(
            UserPreferences(username: "new-account", tokscaleVersion: "latest", npxPath: "")
        )
        await cli.resumeSubmit()
        await submission.value

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit"])
        XCTAssertEqual(model.firstUseOnboardingState, .verifying(username: "new-account"))
        XCTAssertNil(model.profileState.loadedValue)
    }

    func testFirstSubmissionFailureCanRetryWithoutFetching() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder, totalTokens: 0),
            cli: FakeCLI(recorder: recorder, submitError: TestFailure.unavailable),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )
        await model.load()
        await recorder.reset()

        await model.submitFirstUsage()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit"])
        guard case let .firstSubmission(username, message) = model.firstUseOnboardingState else {
            return XCTFail("A failed submit must remain retryable")
        }
        XCTAssertEqual(username, "youranreus")
        XCTAssertNotNil(message)
    }

    func testFirstSubmissionFetchFailureStaysInSecondStepWithRetryableMessage() async throws {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder, fetchError: TestFailure.unavailable),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: try completeSnapshot(
                fetchedAt: referenceDate,
                totalTokens: 0
            )),
            now: { self.referenceDate }
        )

        await model.submitFirstUsage()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit", "fetch"])
        guard case let .firstSubmission(_, message) = model.firstUseOnboardingState else {
            return XCTFail("A post-submit read failure must remain on the second step")
        }
        XCTAssertTrue(message?.contains("统计读取失败") == true)
    }

    func testFirstSubmissionRemainingZeroOrMissingStaysInSecondStepWithGuidance() async {
        for error in [nil, TokscaleAPIError.profileNotFound as Error?] {
            let recorder = EventRecorder()
            let api = FakeAPI(recorder: recorder, fetchError: error, totalTokens: 0)
            let model = DashboardViewModel(
                api: api,
                cli: FakeCLI(recorder: recorder),
                preferencesStore: standardPreferences(),
                npxLocator: FakeNpxLocator(),
                cacheStore: InMemoryCache()
            )
            await model.load()
            await recorder.reset()

            await model.submitFirstUsage()

            let events = await recorder.snapshot()
            XCTAssertEqual(events, ["submit", "fetch"])
            guard case let .firstSubmission(username, message) = model.firstUseOnboardingState else {
                return XCTFail("No visible usage must remain on the second step")
            }
            XCTAssertEqual(username, "youranreus")
            XCTAssertNotNil(message)
        }
    }

    func testModifyUsernameReturnsToEntryWithoutClearingSavedValue() async {
        let recorder = EventRecorder()
        let model = makeViewModel(
            recorder: recorder,
            api: FakeAPI(recorder: recorder, totalTokens: 0)
        )
        await model.load()

        model.editOnboardingUsername()

        XCTAssertEqual(model.firstUseOnboardingState, .usernameEntry(message: nil))
        XCTAssertEqual(model.preferences.username, "youranreus")
    }

    func testProfileNotFoundDuringOrdinaryCachedRefreshKeepsDashboardAndRetrySemantics() async throws {
        let recorder = EventRecorder()
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let model = makeViewModel(
            recorder: recorder,
            api: FakeAPI(recorder: recorder, fetchError: TokscaleAPIError.profileNotFound),
            cache: InMemoryCache(snapshot: snapshot),
            now: { self.referenceDate.addingTimeInterval(301) }
        )

        await model.load()

        XCTAssertEqual(model.firstUseOnboardingState, .hidden)
        XCTAssertEqual(model.profileState.loadedValue, snapshot.profile)
        XCTAssertNotNil(model.loadErrorMessage)
        await model.retryStatistics()
        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "fetch" }.count, 2)
        XCTAssertFalse(events.contains("submit"))
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

    func testUpdatingGeneralPreferencesPersistsNormalizedValuesWithoutExternalWork() async throws {
        let recorder = EventRecorder()
        let preferences = standardPreferences()
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let cache = InMemoryCache(snapshot: snapshot)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: preferences,
            npxLocator: FakeNpxLocator(),
            cacheStore: cache,
            now: { self.referenceDate }
        )
        let updated = UserPreferences(
            username: "  youranreus  ",
            tokscaleVersion: "  4.15.0  ",
            npxPath: "  /custom/npx  ",
            statusTextEnabled: true,
            statusTextTemplate: "月度 {token} / {cost} / {unknown} ",
            statusTextPeriod: .month
        )

        model.updatePreferences(updated)

        let normalized = UserPreferences(
            username: "youranreus",
            tokscaleVersion: "4.15.0",
            npxPath: "/custom/npx",
            statusTextEnabled: true,
            statusTextTemplate: updated.statusTextTemplate,
            statusTextPeriod: .month
        )
        XCTAssertEqual(preferences.value, normalized)
        XCTAssertEqual(model.preferences, normalized)
        XCTAssertEqual(model.profileState.loadedValue, snapshot.profile)
        XCTAssertEqual(model.cacheSavedAt, referenceDate)
        XCTAssertEqual(cache.snapshot?.fetchedAt, referenceDate)
        let month = try XCTUnwrap(snapshot.profiles.first { $0.data.period == .month }?.data)
        XCTAssertEqual(
            model.statusItemTitle,
            StatusItemTextRenderer.render(template: updated.statusTextTemplate, data: month)
        )
        let events = await recorder.snapshot()
        XCTAssertEqual(events, [])
    }

    func testApplyingEnabledAutosubmitOnlyConfiguresAndReadsStatus() async throws {
        let recorder = EventRecorder()
        let preferences = standardPreferences()
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let cache = InMemoryCache(snapshot: snapshot)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: preferences,
            npxLocator: FakeNpxLocator(),
            cacheStore: cache,
            now: { self.referenceDate.addingTimeInterval(60) }
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

        let applied = await model.applyAutosubmit(configuration)

        XCTAssertTrue(applied)
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["configure", "status"])
        XCTAssertEqual(model.operation, .succeeded("自动提交设置已应用。"))
        XCTAssertEqual(model.profileState.loadedValue, snapshot.profile)
        XCTAssertEqual(model.cacheSavedAt, referenceDate)
        XCTAssertEqual(cache.snapshot?.fetchedAt, referenceDate)
        XCTAssertEqual(preferences.value, standardPreferences().value)
    }

    func testApplyingDisabledAutosubmitOnlyDisablesAndReadsStatus() async {
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder)
        let configuration = AutosubmitConfiguration(
            enabled: false,
            intervalMinutes: 120,
            clients: [],
            filterKind: .all,
            year: "",
            since: "",
            until: ""
        )

        let applied = await model.applyAutosubmit(configuration)

        XCTAssertTrue(applied)
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["disable", "status"])
    }

    func testEnabledAutosubmitMutationFailureStopsBeforeStatusRead() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, autosubmitMutationError: TestFailure.unavailable),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )
        let configuration = AutosubmitConfiguration(
            enabled: true,
            intervalMinutes: 120,
            clients: [],
            filterKind: .all,
            year: "",
            since: "",
            until: ""
        )

        let applied = await model.applyAutosubmit(configuration)

        XCTAssertFalse(applied)
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["configure"])
        guard case .failed = model.operation else {
            return XCTFail("Expected the mutation failure to remain visible")
        }
    }

    func testDisabledAutosubmitMutationFailureStopsBeforeStatusRead() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, autosubmitMutationError: TestFailure.unavailable),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )
        let configuration = AutosubmitConfiguration(
            enabled: false,
            intervalMinutes: 120,
            clients: [],
            filterKind: .all,
            year: "",
            since: "",
            until: ""
        )

        let applied = await model.applyAutosubmit(configuration)

        XCTAssertFalse(applied)
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["disable"])
        guard case .failed = model.operation else {
            return XCTFail("Expected the mutation failure to remain visible")
        }
    }

    func testAutosubmitStatusFailureAfterApplyPreservesCachedStatisticsAndReportsPartialSuccess() async throws {
        let recorder = EventRecorder()
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, statusError: TestFailure.unavailable),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: snapshot),
            now: { self.referenceDate.addingTimeInterval(60) }
        )
        let oldStatus = model.currentAutosubmitStatus
        let configuration = AutosubmitConfiguration(
            enabled: true,
            intervalMinutes: 120,
            clients: [],
            filterKind: .all,
            year: "",
            since: "",
            until: ""
        )

        let applied = await model.applyAutosubmit(configuration)

        XCTAssertFalse(applied)
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["configure", "status"])
        XCTAssertEqual(model.currentAutosubmitStatus, oldStatus)
        XCTAssertEqual(model.cacheSavedAt, referenceDate)
        guard case let .failed(message) = model.operation else {
            return XCTFail("Expected the status reread failure to remain visible")
        }
        XCTAssertTrue(message.hasPrefix("自动提交设置已应用，但状态读取失败："))
    }

    func testCLIContextChangeRejectsLateAutosubmitStatusWithoutClearingProfiles() async throws {
        let cli = ControlledStatusCLI()
        let recorder = EventRecorder()
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: cli,
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: snapshot),
            now: { self.referenceDate.addingTimeInterval(299) }
        )
        let oldStatus = try XCTUnwrap(model.currentAutosubmitStatus)
        let load = Task { await model.load() }
        await cli.waitForStatusRequest()

        model.updatePreferences(UserPreferences(
            username: "youranreus",
            tokscaleVersion: "4.15.0",
            npxPath: "/new/npx"
        ))
        await cli.resolveStatus(enabled: false)
        await load.value

        XCTAssertEqual(model.currentAutosubmitStatus, oldStatus)
        XCTAssertEqual(model.profileState.loadedValue, snapshot.profile)
        XCTAssertEqual(model.cacheSavedAt, referenceDate)
        let events = await recorder.snapshot()
        XCTAssertTrue(events.isEmpty)
    }

    func testCaseOnlyUsernameChangeKeepsSameAccountCache() async throws {
        let recorder = EventRecorder()
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let model = makeViewModel(
            recorder: recorder,
            cache: InMemoryCache(snapshot: snapshot),
            now: { self.referenceDate }
        )

        model.updatePreferences(UserPreferences(
            username: "YOURANREUS",
            tokscaleVersion: "latest",
            npxPath: ""
        ))

        XCTAssertEqual(model.profileState.loadedValue, snapshot.profile)
        XCTAssertEqual(model.cacheSavedAt, referenceDate)
        let events = await recorder.snapshot()
        XCTAssertTrue(events.isEmpty)
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

    func testUsernameChangeImmediatelyClearsOldCacheAndRejectsLateBatchWithoutRefetching() async throws {
        let api = ControlledBatchAPI()
        let recorder = EventRecorder()
        let preferences = InMemoryPreferences(
            value: UserPreferences(username: "old", tokscaleVersion: "latest", npxPath: "")
        )
        let cache = InMemoryCache(snapshot: try completeSnapshot(
            fetchedAt: referenceDate,
            username: "old"
        ))
        let model = DashboardViewModel(
            api: api,
            cli: FakeCLI(recorder: recorder),
            preferencesStore: preferences,
            npxLocator: FakeNpxLocator(),
            cacheStore: cache,
            now: { self.referenceDate.addingTimeInterval(301) }
        )
        XCTAssertEqual(model.profileState.loadedValue?.username, "old")

        let load = Task { await model.load() }
        await api.waitForRequest(username: "old")
        model.updatePreferences(
            UserPreferences(username: "new", tokscaleVersion: "latest", npxPath: "")
        )

        XCTAssertNil(model.profileState.loadedValue)
        XCTAssertNil(model.identityProfile)
        XCTAssertNil(model.cacheSavedAt)
        XCTAssertEqual(model.preferences.username, "new")
        XCTAssertEqual(model.firstUseOnboardingState, .verifying(username: "new"))
        XCTAssertEqual(cache.snapshot?.username, "new")
        XCTAssertTrue(cache.snapshot?.profiles.isEmpty == true)
        XCTAssertNil(cache.snapshot?.fetchedAt)
        var requestCount = await api.requestCount()
        XCTAssertEqual(requestCount, 1)

        await api.resolve(username: "old")
        await load.value

        XCTAssertNil(model.profileState.loadedValue)
        XCTAssertEqual(model.preferences.username, "new")
        requestCount = await api.requestCount()
        XCTAssertEqual(requestCount, 1)
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

    private func completeSnapshot(
        fetchedAt: Date,
        username: String = "youranreus",
        totalTokens: Double? = nil
    ) throws -> DashboardCacheSnapshot {
        let batch = try makeBatch(username: username, totalTokens: totalTokens)
        let profiles = ProfilePeriod.allCases.compactMap { period in
            batch.profiles[period].map { CachedDashboardProfile(data: $0, savedAt: fetchedAt) }
        }
        return DashboardCacheSnapshot(
            profile: batch.profiles[.all],
            autosubmit: try makeAutosubmitStatus(),
            savedAt: fetchedAt,
            profiles: profiles,
            username: username,
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
    func reset() { values.removeAll() }
}

private final class FakeAPI: TokscaleAPIService {
    let recorder: EventRecorder
    let fetchError: Error?
    let totalTokens: Double?
    let includesClients: Bool

    init(
        recorder: EventRecorder,
        fetchError: Error? = nil,
        totalTokens: Double? = nil,
        includesClients: Bool = true
    ) {
        self.recorder = recorder
        self.fetchError = fetchError
        self.totalTokens = totalTokens
        self.includesClients = includesClients
    }

    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch {
        await recorder.append("fetch")
        if let fetchError { throw fetchError }
        return try makeBatch(
            username: username,
            totalTokens: totalTokens,
            includesClients: includesClients
        )
    }
}

private func makeBatch(
    username: String,
    totalTokens: Double? = nil,
    includesClients: Bool = true
) throws -> DashboardProfileBatch {
    var profiles: [ProfilePeriod: DashboardData] = [:]
    for period in ProfilePeriod.allCases {
        let response = try JSONDecoder().decode(
            PublicProfileResponse.self,
            from: try scopedFixture(
                period: period,
                username: username,
                totalTokens: totalTokens,
                includesClients: includesClients
            )
        )
        profiles[period] = DashboardData(response: response)
    }
    return try DashboardProfileBatch(username: username, profiles: profiles)
}

private func scopedFixture(
    period: ProfilePeriod,
    username: String,
    totalTokens: Double? = nil,
    includesClients: Bool = true
) throws -> Data {
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ProfileModelsTests.profileJSON.utf8)) as? [String: Any])
    json["period"] = period.rawValue
    var user = try XCTUnwrap(json["user"] as? [String: Any])
    user["username"] = username
    json["user"] = user
    if let totalTokens {
        var stats = try XCTUnwrap(json["stats"] as? [String: Any])
        stats["totalTokens"] = totalTokens
        json["stats"] = stats
    }
    if !includesClients { json["contributions"] = [] }
    return try JSONSerialization.data(withJSONObject: json)
}

private final class FakeCLI: TokscaleCLIService {
    let recorder: EventRecorder
    let submitError: Error?
    let statusError: Error?
    let autosubmitMutationError: Error?
    let discoveredUsername: String
    let whoAmIError: Error?

    init(
        recorder: EventRecorder,
        submitError: Error? = nil,
        statusError: Error? = nil,
        autosubmitMutationError: Error? = nil,
        discoveredUsername: String = "youranreus",
        whoAmIError: Error? = nil
    ) {
        self.recorder = recorder
        self.submitError = submitError
        self.statusError = statusError
        self.autosubmitMutationError = autosubmitMutationError
        self.discoveredUsername = discoveredUsername
        self.whoAmIError = whoAmIError
    }

    func whoAmI(context: TokscaleCommandContext) async throws -> String {
        await recorder.append("whoami")
        if let whoAmIError { throw whoAmIError }
        return discoveredUsername
    }
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
        if let autosubmitMutationError { throw autosubmitMutationError }
    }
    func disableAutosubmit(context: TokscaleCommandContext) async throws {
        await recorder.append("disable")
        if let autosubmitMutationError { throw autosubmitMutationError }
    }
    func runAutosubmitNow(context: TokscaleCommandContext) async throws { await recorder.append("run") }
}

private actor ControlledStatusCLI: TokscaleCLIService {
    private var statusContinuation: CheckedContinuation<AutosubmitStatus, Error>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var statusRequested = false

    func whoAmI(context: TokscaleCommandContext) async throws -> String { "youranreus" }
    func submit(context: TokscaleCommandContext) async throws {}

    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        statusRequested = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        return try await withCheckedThrowingContinuation { statusContinuation = $0 }
    }

    func waitForStatusRequest() async {
        if statusRequested { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func resolveStatus(enabled: Bool) {
        do {
            let status = try JSONDecoder().decode(
                AutosubmitStatus.self,
                from: Data("{\"enabled\":\(enabled)}".utf8)
            )
            statusContinuation?.resume(returning: status)
        } catch {
            statusContinuation?.resume(throwing: error)
        }
        statusContinuation = nil
    }

    func configureAutosubmit(
        _ configuration: AutosubmitConfiguration,
        context: TokscaleCommandContext
    ) async throws {}
    func disableAutosubmit(context: TokscaleCommandContext) async throws {}
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {}
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

private actor SequencedBatchAPI: TokscaleAPIService {
    private let recorder: EventRecorder
    private var totalTokens: [Double?]

    init(recorder: EventRecorder, totalTokens: [Double?]) {
        self.recorder = recorder
        self.totalTokens = totalTokens
    }

    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch {
        await recorder.append("fetch")
        let nextTotal = totalTokens.isEmpty ? nil : totalTokens.removeFirst()
        return try makeBatch(username: username, totalTokens: nextTotal)
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

    func resolve(username: String, totalTokens: Double? = nil) {
        do {
            pending.removeValue(forKey: username)?.resume(
                returning: try makeBatch(username: username, totalTokens: totalTokens)
            )
        } catch {
            pending.removeValue(forKey: username)?.resume(throwing: error)
        }
    }

    func reject(username: String) {
        pending.removeValue(forKey: username)?.resume(throwing: TestFailure.unavailable)
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
