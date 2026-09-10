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

        await model.refreshStatisticsNow()

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

    func testEmptyUsernameLaunchDoesNotDiscoverIdentityOrFetchStatistics() async {
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

        XCTAssertEqual(model.firstUseOnboardingState, .usernameEntry(message: nil))

        await model.load()

        XCTAssertEqual(preferences.value.username, "")
        XCTAssertEqual(model.firstUseOnboardingState, .usernameEntry(message: nil))
        let events = await recorder.snapshot()
        XCTAssertFalse(events.contains("whoami"))
        XCTAssertFalse(events.contains("fetch"))
        XCTAssertEqual(events.filter { $0 == "status" }.count, 1)
    }

    func testEmptyUsernameManualTransferActionsDoNotImplicitlyDiscoverIdentity() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: InMemoryPreferences(
                value: UserPreferences(username: "", tokscaleVersion: "latest", npxPath: "")
            ),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        await model.submitUsageAndRefreshStatistics()
        await model.runAutosubmitNow()

        let events = await recorder.snapshot()
        XCTAssertFalse(events.contains("whoami"))
        XCTAssertFalse(events.contains("submit"))
        XCTAssertFalse(events.contains("run"))
    }

    func testExplicitIdentityDiscoveryPersistsUsernameAndVerifiesUsageOnce() async {
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

        await model.discoverIdentity()

        XCTAssertEqual(preferences.value.username, "youranreus")
        XCTAssertEqual(model.firstUseOnboardingState, .hidden)
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["whoami", "fetch"])
    }

    func testExplicitIdentityFailureReturnsToEditableUsernameEntryAndCanRetry() async {
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

        await model.discoverIdentity()
        await model.discoverIdentity()

        guard case let .usernameEntry(message) = model.firstUseOnboardingState else {
            return XCTFail("Identity discovery failure must allow manual username entry")
        }
        XCTAssertNotNil(message)
        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "whoami" }.count, 2)
        XCTAssertFalse(events.contains("fetch"))
    }

    func testCursorLoginRunsOnceWithoutFollowUpWorkAndPublishesSuccess() async {
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder)

        await model.loginCursor()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["cursor-login"])
        XCTAssertEqual(model.cursorLoginState, .succeeded("Cursor 登录成功。"))
        XCTAssertEqual(model.operation, .idle)
    }

    func testCursorLoginFailureIncludesVersionSpecificTerminalFallback() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, cursorLoginError: TestFailure.unavailable),
            preferencesStore: InMemoryPreferences(value: UserPreferences(
                username: "youranreus",
                tokscaleVersion: "4.15.0",
                npxPath: ""
            )),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        await model.loginCursor()

        guard case let .failed(message, fallbackCommand) = model.cursorLoginState else {
            return XCTFail("Expected recoverable Cursor login failure")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(fallbackCommand, "npx tokscale@4.15.0 cursor login")
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["cursor-login"])
    }

    func testCursorLoginTimeoutRemainsRecoverableWithTerminalFallback() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, cursorLoginError: ProcessRunnerError.timedOut),
            preferencesStore: InMemoryPreferences(value: UserPreferences(
                username: "youranreus",
                tokscaleVersion: "4.15.0",
                npxPath: ""
            )),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        await model.loginCursor()

        guard case let .failed(message, fallbackCommand) = model.cursorLoginState else {
            return XCTFail("Expected recoverable Cursor login timeout")
        }
        XCTAssertEqual(message, "Tokscale 运行超时，已停止该进程。")
        XCTAssertEqual(fallbackCommand, "npx tokscale@4.15.0 cursor login")
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["cursor-login"])
        XCTAssertEqual(model.operation, .idle)
    }

    func testInvalidCursorLoginContextDoesNotLaunchCLIAndUsesSafeFallback() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: InMemoryPreferences(value: UserPreferences(
                username: "youranreus",
                tokscaleVersion: "latest;rm",
                npxPath: ""
            )),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        await model.loginCursor()

        guard case let .failed(message, fallbackCommand) = model.cursorLoginState else {
            return XCTFail("Expected invalid version failure")
        }
        XCTAssertTrue(message.contains("语义化版本号"))
        XCTAssertEqual(fallbackCommand, "npx tokscale@latest cursor login")
        let events = await recorder.snapshot()
        XCTAssertTrue(events.isEmpty)
    }

    func testMissingNpxCursorLoginDoesNotLaunchCLIAndRemainsRecoverable() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: InMemoryPreferences(value: UserPreferences(
                username: "youranreus",
                tokscaleVersion: "4.15.0",
                npxPath: ""
            )),
            npxLocator: MissingNpxLocator(),
            cacheStore: InMemoryCache()
        )

        await model.loginCursor()

        guard case let .failed(message, fallbackCommand) = model.cursorLoginState else {
            return XCTFail("Expected missing npx failure")
        }
        XCTAssertTrue(message.contains("找不到 npx"))
        XCTAssertEqual(fallbackCommand, "npx tokscale@4.15.0 cursor login")
        let events = await recorder.snapshot()
        XCTAssertTrue(events.isEmpty)
    }

    func testCursorLoginRejectsDuplicateAndConflictingExplicitActions() async {
        let recorder = EventRecorder()
        let cli = SuspendedCursorLoginCLI(recorder: recorder)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: cli,
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        let login = Task { await model.loginCursor() }
        await cli.waitForLogin()
        XCTAssertEqual(model.cursorLoginState, .loggingIn)
        XCTAssertTrue(model.isPerformingOperation)

        await model.loginCursor()
        await model.submitUsageAndRefreshStatistics()
        var events = await recorder.snapshot()
        XCTAssertEqual(events, ["cursor-login"])

        await cli.resumeLogin()
        await login.value
        events = await recorder.snapshot()
        XCTAssertEqual(events, ["cursor-login"])
        XCTAssertEqual(model.cursorLoginState, .succeeded("Cursor 登录成功。"))
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

    func testSubmitAndRefreshSubmitsBeforeReadingEveryRange() async {
        let recorder = EventRecorder()
        let cache = InMemoryCache()
        let model = makeViewModel(recorder: recorder, cache: cache)

        await model.submitUsageAndRefreshStatistics()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit", "fetch"])
        XCTAssertEqual(Set(cache.snapshot?.profiles.map(\.data.period) ?? []), Set(ProfilePeriod.allCases))
        XCTAssertNotNil(cache.snapshot?.fetchedAt)
        XCTAssertEqual(model.operation, .succeeded("用量已提交，统计读取完成。"))
    }

    func testReadOnlyRefreshFetchesExactlyOneCompleteBatchWithoutSubmitting() async {
        let recorder = EventRecorder()
        let cache = InMemoryCache()
        let model = makeViewModel(recorder: recorder, cache: cache)

        await model.refreshStatisticsNow()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["fetch"])
        XCTAssertEqual(Set(cache.snapshot?.profiles.map(\.data.period) ?? []), Set(ProfilePeriod.allCases))
        XCTAssertEqual(model.operation, .idle)
    }

    func testReadOnlyRefreshFailureAppearsInDiagnostics() async {
        let recorder = EventRecorder()
        let model = makeViewModel(
            recorder: recorder,
            api: FakeAPI(recorder: recorder, fetchError: TestFailure.unavailable)
        )

        await model.refreshStatisticsNow()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["fetch"])
        XCTAssertNotNil(model.loadErrorMessage)
        XCTAssertTrue(model.diagnosticMessages.contains { $0.hasPrefix("统计读取：") })
    }

    func testRunningSubmitRejectsReadOnlyRefreshAndDuplicateSubmit() async {
        let recorder = EventRecorder()
        let cli = SuspendedPushCLI(recorder: recorder)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: cli,
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        let firstSubmit = Task { await model.submitUsageAndRefreshStatistics() }
        await cli.waitForSubmit()
        XCTAssertEqual(model.operation, .submitting)

        await model.refreshStatisticsNow()
        await model.submitUsageAndRefreshStatistics()
        var events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit"])

        await cli.resumeSubmit()
        await firstSubmit.value
        events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit", "fetch"])
        XCTAssertEqual(model.operation, .succeeded("用量已提交，统计读取完成。"))
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

        await model.submitUsageAndRefreshStatistics()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit"])
        guard case .failed = model.operation else { return XCTFail("Expected failed operation") }
        // The status menu runs this action with the popover closed, so the banner is suppressed.
        XCTAssertTrue(model.diagnosticMessages.contains { $0.hasPrefix("用量提交：") })
    }

    func testASucceedingSubmitClearsAPreviousSubmitDiagnostic() async {
        let recorder = EventRecorder()
        let failingCLI = FakeCLI(recorder: recorder, submitError: TestFailure.unavailable)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: failingCLI,
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )

        await model.submitUsageAndRefreshStatistics()
        XCTAssertNotNil(model.submitErrorMessage)

        failingCLI.submitError = nil
        await model.submitUsageAndRefreshStatistics()

        XCTAssertNil(model.submitErrorMessage)
        XCTAssertFalse(model.diagnosticMessages.contains { $0.hasPrefix("用量提交：") })
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

    func testAvailableClientIDsUnitesEveryCachedPeriodAndPersistedAbsentSelections() throws {
        let snapshot = try snapshotWithDistinctClients(fetchedAt: referenceDate)
        let preferences = InMemoryPreferences(value: UserPreferences(
            username: "youranreus",
            tokscaleVersion: "latest",
            npxPath: "",
            hiddenClientIDs: [" selected-absent ", "cursor"]
        ))
        let model = DashboardViewModel(
            api: FakeAPI(recorder: EventRecorder()),
            cli: FakeCLI(recorder: EventRecorder()),
            preferencesStore: preferences,
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: snapshot),
            now: { self.referenceDate }
        )

        XCTAssertEqual(
            model.availableClientIDs,
            ["amp", "codex", "cursor", "selected-absent", "zed"]
        )
    }

    func testUpdatingDisplayPreferencesNormalizesAndPersistsWithoutExternalWorkOrCacheWrites() async throws {
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
        var updated = model.preferences
        updated.hideZeroCostModels = true
        updated.hiddenClientsEnabled = true
        updated.hiddenClientIDs = [" cursor ", "", "\n", "cursor", "absent"]

        model.updatePreferences(updated)

        XCTAssertTrue(model.preferences.hideZeroCostModels)
        XCTAssertTrue(model.preferences.hiddenClientsEnabled)
        XCTAssertEqual(model.preferences.hiddenClientIDs, ["cursor", "absent"])
        XCTAssertEqual(preferences.value, model.preferences)
        XCTAssertEqual(cache.snapshot, snapshot)
        XCTAssertEqual(cache.saveCount, 0)
        let events = await recorder.snapshot()
        XCTAssertTrue(events.isEmpty)
    }

    func testUpdatingGeneralPreferencesPersistsNormalizedValuesWithoutStatisticsWork() async throws {
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
        // A CLI context change reads autosubmit status only; statistics stay untouched.
        for _ in 0..<20 { await Task.yield() }
        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 != "status" }, [])
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
        let refresh = Task { await model.submitUsageAndRefreshStatistics() }
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
        XCTAssertEqual(model.operation, .succeeded("用量已提交，统计读取完成。"))
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

    func testBackgroundSchedulerKeepsRefreshingWhileThePanelIsClosed() async throws {
        let recorder = EventRecorder()
        let clock = TestClock(referenceDate)
        let sleeper = ManualSleeper()
        let model = makeScheduledViewModel(
            recorder: recorder,
            cache: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            clock: clock,
            sleeper: sleeper
        )

        model.startBackgroundSynchronization()
        await sleeper.waitUntilSleeping()
        let firstDelay = await sleeper.requestedNanoseconds()
        XCTAssertEqual(firstDelay, 300_000_000_000)

        clock.value.addTimeInterval(300)
        await sleeper.advance()
        await waitForFetchCount(1, recorder: recorder)
        await sleeper.waitUntilSleeping()

        model.stopBackgroundSynchronization()
        await sleeper.advance()

        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "fetch" }.count, 1)
        XCTAssertEqual(model.cacheSavedAt, clock.value)
        XCTAssertFalse(events.contains("submit"))
        XCTAssertFalse(events.contains("run"))
        XCTAssertFalse(events.contains("configure"))
        XCTAssertFalse(events.contains("disable"))
    }

    func testStartingBackgroundSynchronizationTwiceKeepsOneScheduler() async throws {
        let recorder = EventRecorder()
        let clock = TestClock(referenceDate)
        let sleeper = ManualSleeper()
        let model = makeScheduledViewModel(
            recorder: recorder,
            cache: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            clock: clock,
            sleeper: sleeper
        )

        model.startBackgroundSynchronization()
        model.startBackgroundSynchronization()
        await sleeper.waitUntilSleeping()
        let sleepCount = await sleeper.sleepCount()
        XCTAssertEqual(sleepCount, 1)

        clock.value.addTimeInterval(300)
        await sleeper.advance()
        await waitForFetchCount(1, recorder: recorder)
        await sleeper.waitUntilSleeping()
        model.stopBackgroundSynchronization()
        await sleeper.advance()

        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "fetch" }.count, 1)
    }

    func testPanelVisibilityNeverStartsOrStopsStatisticsScheduling() async throws {
        let recorder = EventRecorder()
        let clock = TestClock(referenceDate)
        let sleeper = ManualSleeper()
        let model = makeScheduledViewModel(
            recorder: recorder,
            cache: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            clock: clock,
            sleeper: sleeper
        )

        model.panelDidAppear()
        model.panelDidDisappear()
        model.panelDidAppear()
        model.panelDidDisappear()
        for _ in 0..<10 { await Task.yield() }
        var sleepCount = await sleeper.sleepCount()
        var events = await recorder.snapshot()
        XCTAssertEqual(sleepCount, 0)
        XCTAssertTrue(events.isEmpty)

        model.startBackgroundSynchronization()
        await sleeper.waitUntilSleeping()
        model.panelDidAppear()
        model.panelDidDisappear()
        clock.value.addTimeInterval(300)
        await sleeper.advance()
        await waitForFetchCount(1, recorder: recorder)
        await sleeper.waitUntilSleeping()
        model.stopBackgroundSynchronization()
        await sleeper.advance()

        sleepCount = await sleeper.sleepCount()
        events = await recorder.snapshot()
        XCTAssertEqual(sleepCount, 2)
        XCTAssertEqual(events.filter { $0 == "fetch" }.count, 1)
    }

    func testBackgroundSchedulerSleepsForTheRemainingFreshnessWindow() async throws {
        let clock = TestClock(referenceDate.addingTimeInterval(240))
        let sleeper = ManualSleeper()
        let model = makeScheduledViewModel(
            recorder: EventRecorder(),
            cache: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            clock: clock,
            sleeper: sleeper
        )

        model.startBackgroundSynchronization()
        await sleeper.waitUntilSleeping()

        let remainingDelay = await sleeper.requestedNanoseconds()
        XCTAssertEqual(remainingDelay, 60_000_000_000)
        model.stopBackgroundSynchronization()
        await sleeper.advance()
    }

    func testBackgroundSchedulerWithoutUsernameStaysSilent() async {
        let recorder = EventRecorder()
        let clock = TestClock(referenceDate)
        let sleeper = ManualSleeper()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, whoAmIError: TestFailure.unavailable),
            preferencesStore: InMemoryPreferences(
                value: UserPreferences(username: "", tokscaleVersion: "latest", npxPath: "")
            ),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(),
            now: { clock.value },
            sleep: { await sleeper.sleep($0) }
        )

        await model.reevaluateStatisticsAfterWake()
        var events = await recorder.snapshot()
        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(model.loadErrorMessage)

        model.startBackgroundSynchronization()
        await waitForEventCount(1, event: "status", recorder: recorder)
        await sleeper.waitUntilSleeping()
        clock.value.addTimeInterval(300)
        await sleeper.advance()
        await sleeper.waitUntilSleeping()
        model.stopBackgroundSynchronization()
        await sleeper.advance()

        events = await recorder.snapshot()
        XCTAssertFalse(events.contains("whoami"))
        XCTAssertFalse(events.contains("fetch"))
        XCTAssertFalse(events.contains("submit"))
        XCTAssertFalse(events.contains("run"))
        XCTAssertFalse(events.contains("configure"))
        XCTAssertFalse(events.contains("disable"))
        XCTAssertNil(model.loadErrorMessage)
    }

    func testWakeWithAFreshSnapshotIssuesNoRequest() async throws {
        let recorder = EventRecorder()
        let model = makeViewModel(
            recorder: recorder,
            cache: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            now: { self.referenceDate.addingTimeInterval(299) }
        )

        await model.reevaluateStatisticsAfterWake()

        let events = await recorder.snapshot()
        XCTAssertTrue(events.isEmpty)
    }

    func testWakeAfterALongSleepReadsOneBatchWithoutCatchingUpMissedPeriods() async throws {
        let recorder = EventRecorder()
        let model = makeViewModel(
            recorder: recorder,
            cache: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            now: { self.referenceDate.addingTimeInterval(4 * 3_600) }
        )

        await model.reevaluateStatisticsAfterWake()
        await model.reevaluateStatisticsAfterWake()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["fetch"])
    }

    func testConcurrentWakeAndSchedulerTriggersCoalesceIntoOneBatch() async {
        let api = ControlledBatchAPI()
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder, api: api)

        let wake = Task { await model.reevaluateStatisticsAfterWake() }
        await api.waitForRequest(username: "youranreus")
        let deadline = Task { await model.reevaluateStatisticsAfterWake() }
        await api.resolve(username: "youranreus")
        await wake.value
        await deadline.value

        let count = await api.requestCount()
        XCTAssertEqual(count, 1)
    }

    func testAutomaticFailureBackoffEscalatesAndResetsAfterSuccess() async throws {
        let recorder = EventRecorder()
        let clock = TestClock(referenceDate.addingTimeInterval(300))
        let api = ToggleableBatchAPI(recorder: recorder, isFailing: true)
        let model = makeViewModel(
            recorder: recorder,
            api: api,
            cache: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            now: { clock.value }
        )

        for backoff in [30.0, 60.0, 300.0, 300.0] {
            let before = await fetchCount(recorder)
            await model.reevaluateStatisticsAfterWake()
            let afterAttempt = await fetchCount(recorder)
            XCTAssertEqual(afterAttempt, before + 1)

            clock.value.addTimeInterval(backoff - 1)
            await model.reevaluateStatisticsAfterWake()
            let insideBackoff = await fetchCount(recorder)
            XCTAssertEqual(
                insideBackoff,
                before + 1,
                "A wake inside the \(backoff)s backoff window must not read"
            )
            clock.value.addTimeInterval(1)
        }

        await api.setFailing(false)
        await model.reevaluateStatisticsAfterWake()
        XCTAssertEqual(model.cacheSavedAt, clock.value)

        await api.setFailing(true)
        clock.value.addTimeInterval(300)
        await model.reevaluateStatisticsAfterWake()
        let failedAgainAt = await fetchCount(recorder)
        clock.value.addTimeInterval(29)
        await model.reevaluateStatisticsAfterWake()
        let insideFirstStep = await fetchCount(recorder)
        XCTAssertEqual(insideFirstStep, failedAgainAt)
        clock.value.addTimeInterval(1)
        await model.reevaluateStatisticsAfterWake()
        let afterFirstStep = await fetchCount(recorder)
        XCTAssertEqual(
            afterFirstStep,
            failedAgainAt + 1,
            "A successful batch must reset the backoff to its first step"
        )
    }

    func testUserRequestedReadBypassesAutomaticBackoffAndKeepsOldSnapshot() async throws {
        let recorder = EventRecorder()
        let clock = TestClock(referenceDate.addingTimeInterval(300))
        let model = makeViewModel(
            recorder: recorder,
            api: FakeAPI(recorder: recorder, fetchError: TestFailure.unavailable),
            cache: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            now: { clock.value }
        )

        await model.reevaluateStatisticsAfterWake()
        await model.reevaluateStatisticsAfterWake()
        var fetches = await fetchCount(recorder)
        XCTAssertEqual(fetches, 1)

        await model.refreshStatisticsNow()

        fetches = await fetchCount(recorder)
        XCTAssertEqual(fetches, 2)
        XCTAssertEqual(model.cacheSavedAt, referenceDate)
        XCTAssertNotNil(model.profileState.loadedValue)
    }

    func testApplicationLaunchReadsStatisticsAndStatusWithoutMutatingAnything() async throws {
        let recorder = EventRecorder()
        let clock = TestClock(referenceDate.addingTimeInterval(300))
        let sleeper = ManualSleeper()
        let model = makeScheduledViewModel(
            recorder: recorder,
            cache: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            clock: clock,
            sleeper: sleeper
        )

        model.startBackgroundSynchronization()
        await waitForFetchCount(1, recorder: recorder)
        await waitForEventCount(1, event: "status", recorder: recorder)
        await sleeper.waitUntilSleeping()
        model.stopBackgroundSynchronization()
        await sleeper.advance()

        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "fetch" }.count, 1)
        XCTAssertEqual(events.filter { $0 == "status" }.count, 1)
        XCTAssertEqual(Set(events), Set(["fetch", "status"]))
    }

    func testSettingsVisibilityReadsBothStatusesOncePerContinuousVisiblePeriod() async {
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder)

        model.settingsDidBecomeVisible()
        model.settingsDidBecomeVisible()
        await waitForEventCount(1, event: "status", recorder: recorder)
        await waitForEventCount(1, event: "cursor-status", recorder: recorder)
        var events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "status" }.count, 1)
        XCTAssertEqual(events.filter { $0 == "cursor-status" }.count, 1)
        XCTAssertEqual(model.cursorConnectionState, .loggedIn)

        model.settingsDidBecomeHidden()
        XCTAssertEqual(model.cursorConnectionState, .idle)
        model.settingsDidBecomeVisible()
        await waitForEventCount(2, event: "status", recorder: recorder)
        await waitForEventCount(2, event: "cursor-status", recorder: recorder)

        events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "status" }.count, 2)
        XCTAssertEqual(events.filter { $0 == "cursor-status" }.count, 2)
        XCTAssertFalse(events.contains("fetch"))
    }

    func testCursorStatusUnavailableOffersLoginWhileIndeterminateAndErrorsOfferRetryOnly() async {
        let cases: [(CursorSessionStatus, CursorConnectionState)] = [
            (.unavailable, .needsLogin),
            (.indeterminate, .checkFailed("无法确认 Cursor 登录状态，请重新检查。"))
        ]
        for (status, expected) in cases {
            let recorder = EventRecorder()
            let model = DashboardViewModel(
                api: FakeAPI(recorder: recorder),
                cli: FakeCLI(recorder: recorder, cursorSessionStatus: status),
                preferencesStore: standardPreferences(),
                npxLocator: FakeNpxLocator(),
                cacheStore: InMemoryCache()
            )

            model.settingsDidBecomeVisible()
            await waitForEventCount(1, event: "cursor-status", recorder: recorder)
            for _ in 0..<20 where model.cursorConnectionState == .checking { await Task.yield() }

            XCTAssertEqual(model.cursorConnectionState, expected)
            XCTAssertEqual(model.cursorConnectionState.showsLoginAction, status == .unavailable)
            XCTAssertEqual(model.cursorConnectionState.showsRetryAction, status == .indeterminate)
            model.settingsDidBecomeHidden()
        }

        let recorder = EventRecorder()
        let failedModel = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, cursorStatusError: TestFailure.unavailable),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )
        failedModel.settingsDidBecomeVisible()
        await waitForEventCount(1, event: "cursor-status", recorder: recorder)
        for _ in 0..<20 where failedModel.cursorConnectionState == .checking { await Task.yield() }
        XCTAssertEqual(
            failedModel.cursorConnectionState,
            .checkFailed("Cursor 状态检查失败，请重新检查。")
        )
        XCTAssertFalse(failedModel.cursorConnectionState.showsLoginAction)
        XCTAssertTrue(failedModel.cursorConnectionState.showsRetryAction)
    }

    func testCursorStatusRetryRunsOneAdditionalReadWithoutOtherWork() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, cursorSessionStatus: .indeterminate),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )
        model.settingsDidBecomeVisible()
        await waitForEventCount(1, event: "cursor-status", recorder: recorder)
        for _ in 0..<20 where model.cursorConnectionState == .checking { await Task.yield() }

        model.retryCursorStatus()
        model.retryCursorStatus()
        await waitForEventCount(2, event: "cursor-status", recorder: recorder)

        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "cursor-status" }.count, 2)
        XCTAssertFalse(events.contains("fetch"))
        XCTAssertFalse(events.contains("submit"))
    }

    func testCursorStatusCheckBlocksConflictingExplicitCLIWork() async {
        let recorder = EventRecorder()
        let cli = SuspendedCursorStatusCLI(recorder: recorder)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: cli,
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )
        model.settingsDidBecomeVisible()
        await cli.waitForCursorStatus()
        XCTAssertEqual(model.cursorConnectionState, .checking)
        XCTAssertTrue(model.isPerformingOperation)

        await model.loginCursor()
        await model.submitUsageAndRefreshStatistics()

        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "cursor-status" }.count, 1)
        XCTAssertFalse(events.contains("cursor-login"))
        XCTAssertFalse(events.contains("submit"))
        await cli.resolveCursorStatus(.valid)
    }

    func testClosingSettingsRejectsLateCursorStatusResult() async {
        let recorder = EventRecorder()
        let cli = SuspendedCursorStatusCLI(recorder: recorder)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: cli,
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )
        model.settingsDidBecomeVisible()
        await cli.waitForCursorStatus()

        model.settingsDidBecomeHidden()
        await cli.resolveCursorStatus(.valid)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(model.cursorConnectionState, .idle)
        XCTAssertEqual(model.cursorLoginState, .idle)
    }

    func testCursorStatusContextChangeRejectsOldResultAndStartsFreshRead() async {
        let recorder = EventRecorder()
        let cli = ContextChangingCursorStatusCLI(recorder: recorder)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: cli,
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )
        model.settingsDidBecomeVisible()
        await cli.waitForFirstCursorStatus()

        model.updatePreferences(UserPreferences(
            username: "youranreus",
            tokscaleVersion: "4.15.0",
            npxPath: ""
        ))
        await cli.waitForCursorStatusCount(2)
        for _ in 0..<20 where model.cursorConnectionState == .checking { await Task.yield() }
        XCTAssertEqual(model.cursorConnectionState, .needsLogin)

        await cli.resolveFirstCursorStatus(.valid)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.cursorConnectionState, .needsLogin)
        let contexts = await cli.cursorContexts()
        XCTAssertEqual(contexts.map(\.version), ["latest", "4.15.0"])
    }

    func testMissingNpxCursorStatusIsRetryOnlyAndDoesNotLaunchCLI() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: standardPreferences(),
            npxLocator: MissingNpxLocator(),
            cacheStore: InMemoryCache()
        )

        model.settingsDidBecomeVisible()
        for _ in 0..<200 {
            if model.cursorConnectionState.showsRetryAction { break }
            await Task.yield()
        }

        XCTAssertFalse(model.cursorConnectionState.showsLoginAction)
        XCTAssertTrue(model.cursorConnectionState.showsRetryAction)
        let events = await recorder.snapshot()
        XCTAssertFalse(events.contains("cursor-status"))
    }

    func testSettingsCursorLoginSuccessProjectsConnectedAndCloseClearsFeedback() async {
        let recorder = EventRecorder()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder, cursorSessionStatus: .unavailable),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache()
        )
        model.settingsDidBecomeVisible()
        await waitForEventCount(1, event: "cursor-status", recorder: recorder)
        for _ in 0..<20 where model.cursorConnectionState == .checking { await Task.yield() }

        await model.loginCursor()

        XCTAssertEqual(model.cursorConnectionState, .loggedIn)
        XCTAssertEqual(model.cursorLoginState, .succeeded("Cursor 登录成功。"))
        model.settingsDidBecomeHidden()
        XCTAssertEqual(model.cursorConnectionState, .idle)
        XCTAssertEqual(model.cursorLoginState, .idle)
    }

    func testAutosubmitStatusRefreshNeverReadsStatistics() async {
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder)

        await model.refreshAutosubmitStatus()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["status"])
        XCTAssertNotNil(model.currentAutosubmitStatus)
    }

    func testChangingTheCLIContextReadsStatusOnceWithoutReadingStatistics() async throws {
        let recorder = EventRecorder()
        let model = makeViewModel(
            recorder: recorder,
            cache: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            now: { self.referenceDate }
        )

        model.updatePreferences(UserPreferences(
            username: "youranreus",
            tokscaleVersion: "4.15.0",
            npxPath: ""
        ))
        await waitForEventCount(1, event: "status", recorder: recorder)
        for _ in 0..<10 { await Task.yield() }

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["status"])
        XCTAssertEqual(model.cacheSavedAt, referenceDate)
    }

    func testChangingOnlyTheAccountRunsNoCommandAtAll() async {
        let recorder = EventRecorder()
        let model = makeViewModel(recorder: recorder)

        model.updatePreferences(UserPreferences(
            username: "another-account",
            tokscaleVersion: "latest",
            npxPath: ""
        ))
        for _ in 0..<20 { await Task.yield() }

        let events = await recorder.snapshot()
        XCTAssertTrue(events.isEmpty)
    }

    func testSubmitSuccessWithFailedReadPreservesTheOldSnapshotAndReportsPartialSuccess() async throws {
        let recorder = EventRecorder()
        let snapshot = try completeSnapshot(fetchedAt: referenceDate)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder, fetchError: TestFailure.unavailable),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: snapshot),
            now: { self.referenceDate.addingTimeInterval(301) }
        )

        await model.submitUsageAndRefreshStatistics()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit", "fetch"])
        XCTAssertEqual(model.cacheSavedAt, referenceDate)
        XCTAssertEqual(model.profileState.loadedValue, snapshot.profile)
        guard case let .failed(message) = model.operation else {
            return XCTFail("A post-submit read failure must stay visible")
        }
        XCTAssertEqual(message.hasPrefix("用量已提交，但统计读取失败："), true)
    }

    func testAccountChangeDuringSuspendedSubmitNeverReadsForTheNewAccount() async throws {
        let recorder = EventRecorder()
        let cli = SuspendedPushCLI(recorder: recorder)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: cli,
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            now: { self.referenceDate }
        )

        let submission = Task { await model.submitUsageAndRefreshStatistics() }
        await cli.waitForSubmit()
        model.updatePreferences(
            UserPreferences(username: "new-account", tokscaleVersion: "latest", npxPath: "")
        )
        await cli.resumeSubmit()
        await submission.value

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["submit"])
        XCTAssertEqual(model.operation, .idle)
        XCTAssertNil(model.profileState.loadedValue)
    }

    func testClockRollbackKeepsAutomaticBackoffAndWaitsAFullInterval() async throws {
        let recorder = EventRecorder()
        let clock = TestClock(referenceDate.addingTimeInterval(300))
        let sleeper = ManualSleeper()
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder, fetchError: TestFailure.unavailable),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            now: { clock.value },
            sleep: { await sleeper.sleep($0) }
        )

        await model.reevaluateStatisticsAfterWake()
        var fetches = await fetchCount(recorder)
        XCTAssertEqual(fetches, 1)

        clock.value = referenceDate.addingTimeInterval(-60)
        await model.reevaluateStatisticsAfterWake()
        fetches = await fetchCount(recorder)
        XCTAssertEqual(fetches, 1)

        model.startBackgroundSynchronization()
        await sleeper.waitUntilSleeping()
        let delay = await sleeper.requestedNanoseconds()
        XCTAssertEqual(delay, 300_000_000_000)
        model.stopBackgroundSynchronization()
        await sleeper.advance()

        fetches = await fetchCount(recorder)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(model.cacheSavedAt, referenceDate)
    }

    func testCLIContextChangeDuringSuspendedApplyNeverReadsWithTheOldContext() async {
        let recorder = EventRecorder()
        let cli = SuspendedMutationCLI(recorder: recorder, kind: .configure)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: cli,
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(),
            now: { self.referenceDate }
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

        let apply = Task { await model.applyAutosubmit(configuration) }
        await cli.waitForMutation()
        model.updatePreferences(
            UserPreferences(username: "youranreus", tokscaleVersion: "4.15.0", npxPath: "")
        )
        await cli.resumeMutation()
        let applied = await apply.value

        XCTAssertFalse(applied)
        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "configure" }, ["configure"])
        XCTAssertFalse(events.contains("fetch"))
        XCTAssertEqual(model.operation, .idle)
        let statusContexts = await cli.statusContexts()
        XCTAssertTrue(statusContexts.allSatisfy { $0.version == "4.15.0" })
    }

    func testCLIContextChangeDuringSuspendedRunNeverReadsForTheNewContext() async throws {
        let recorder = EventRecorder()
        let cli = SuspendedMutationCLI(recorder: recorder, kind: .run)
        let model = DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: cli,
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: InMemoryCache(snapshot: try completeSnapshot(fetchedAt: referenceDate)),
            now: { self.referenceDate }
        )

        let run = Task { await model.runAutosubmitNow() }
        await cli.waitForMutation()
        model.updatePreferences(
            UserPreferences(username: "youranreus", tokscaleVersion: "4.15.0", npxPath: "")
        )
        await cli.resumeMutation()
        await run.value

        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0 == "run" }, ["run"])
        XCTAssertFalse(events.contains("fetch"))
        XCTAssertEqual(model.operation, .idle)
        XCTAssertEqual(model.cacheSavedAt, referenceDate)
        let statusContexts = await cli.statusContexts()
        XCTAssertTrue(statusContexts.allSatisfy { $0.version == "4.15.0" })
    }

    private func waitForFetchCount(_ expected: Int, recorder: EventRecorder) async {
        for _ in 0..<100 {
            if await recorder.snapshot().filter({ $0 == "fetch" }).count >= expected { return }
            await Task.yield()
        }
    }

    private func fetchCount(_ recorder: EventRecorder) async -> Int {
        await recorder.snapshot().filter { $0 == "fetch" }.count
    }

    private func waitForEventCount(_ expected: Int, event: String, recorder: EventRecorder) async {
        for _ in 0..<200 {
            if await recorder.snapshot().filter({ $0 == event }).count >= expected { return }
            await Task.yield()
        }
    }

    private func waitForRequestCount(_ expected: Int, api: QueuedBatchAPI) async {
        for _ in 0..<100 {
            if await api.requestCount() >= expected { return }
            await Task.yield()
        }
    }

    private func makeScheduledViewModel(
        recorder: EventRecorder,
        cache: InMemoryCache,
        clock: TestClock,
        sleeper: ManualSleeper
    ) -> DashboardViewModel {
        DashboardViewModel(
            api: FakeAPI(recorder: recorder),
            cli: FakeCLI(recorder: recorder),
            preferencesStore: standardPreferences(),
            npxLocator: FakeNpxLocator(),
            cacheStore: cache,
            now: { clock.value },
            refreshInterval: 300,
            sleep: { await sleeper.sleep($0) }
        )
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

    private func snapshotWithDistinctClients(fetchedAt: Date) throws -> DashboardCacheSnapshot {
        let clientIDs: [ProfilePeriod: String] = [
            .all: "zed",
            .day: "codex",
            .week: "cursor",
            .month: "amp"
        ]
        let profiles = try ProfilePeriod.allCases.map { period in
            CachedDashboardProfile(
                data: try dashboardData(period: period, clientID: try XCTUnwrap(clientIDs[period])),
                savedAt: fetchedAt
            )
        }
        return DashboardCacheSnapshot(
            profile: profiles.first { $0.data.period == .all }?.data,
            autosubmit: nil,
            savedAt: fetchedAt,
            profiles: profiles,
            username: "youranreus",
            fetchedAt: fetchedAt
        )
    }

    private func dashboardData(period: ProfilePeriod, clientID: String) throws -> DashboardData {
        let json: [String: Any] = [
            "period": period.rawValue,
            "user": ["username": "youranreus", "displayName": "Youran"],
            "stats": ["totalTokens": 1, "totalCost": 0, "activeDays": 1],
            "contributions": [[
                "clients": [[
                    "client": clientID,
                    "models": ["zero-cost-model": ["tokens": 1, "cost": 0]],
                    "tokens": ["input": 1],
                    "cost": 0
                ]]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = try JSONDecoder().decode(PublicProfileResponse.self, from: data)
        return DashboardData(response: response)
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
    var submitError: Error?
    let statusError: Error?
    let autosubmitMutationError: Error?
    let cursorLoginError: Error?
    let cursorSessionStatus: CursorSessionStatus
    let cursorStatusError: Error?
    let discoveredUsername: String
    let whoAmIError: Error?

    init(
        recorder: EventRecorder,
        submitError: Error? = nil,
        statusError: Error? = nil,
        autosubmitMutationError: Error? = nil,
        cursorLoginError: Error? = nil,
        cursorSessionStatus: CursorSessionStatus = .valid,
        cursorStatusError: Error? = nil,
        discoveredUsername: String = "youranreus",
        whoAmIError: Error? = nil
    ) {
        self.recorder = recorder
        self.submitError = submitError
        self.statusError = statusError
        self.autosubmitMutationError = autosubmitMutationError
        self.cursorLoginError = cursorLoginError
        self.cursorSessionStatus = cursorSessionStatus
        self.cursorStatusError = cursorStatusError
        self.discoveredUsername = discoveredUsername
        self.whoAmIError = whoAmIError
    }

    func whoAmI(context: TokscaleCommandContext) async throws -> String {
        await recorder.append("whoami")
        if let whoAmIError { throw whoAmIError }
        return discoveredUsername
    }
    func loginCursor(context: TokscaleCommandContext) async throws {
        await recorder.append("cursor-login")
        if let cursorLoginError { throw cursorLoginError }
    }
    func cursorStatus(context: TokscaleCommandContext) async throws -> CursorSessionStatus {
        await recorder.append("cursor-status")
        if let cursorStatusError { throw cursorStatusError }
        return cursorSessionStatus
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

private actor SuspendedCursorLoginCLI: TokscaleCLIService {
    private let recorder: EventRecorder
    private var loginContinuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var loginStarted = false

    init(recorder: EventRecorder) {
        self.recorder = recorder
    }

    func whoAmI(context: TokscaleCommandContext) async throws -> String { "youranreus" }

    func loginCursor(context: TokscaleCommandContext) async throws {
        await recorder.append("cursor-login")
        loginStarted = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        await withCheckedContinuation { loginContinuation = $0 }
    }

    func cursorStatus(context: TokscaleCommandContext) async throws -> CursorSessionStatus { .valid }

    func waitForLogin() async {
        if loginStarted { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func resumeLogin() {
        loginContinuation?.resume()
        loginContinuation = nil
    }

    func submit(context: TokscaleCommandContext) async throws { await recorder.append("submit") }
    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        await recorder.append("status")
        return try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false}"#.utf8))
    }
    func configureAutosubmit(_ configuration: AutosubmitConfiguration, context: TokscaleCommandContext) async throws {
        await recorder.append("configure")
    }
    func disableAutosubmit(context: TokscaleCommandContext) async throws { await recorder.append("disable") }
    func runAutosubmitNow(context: TokscaleCommandContext) async throws { await recorder.append("run") }
}

private actor SuspendedCursorStatusCLI: TokscaleCLIService {
    private let recorder: EventRecorder
    private var statusContinuation: CheckedContinuation<CursorSessionStatus, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?

    init(recorder: EventRecorder) { self.recorder = recorder }

    func whoAmI(context: TokscaleCommandContext) async throws -> String { "youranreus" }
    func loginCursor(context: TokscaleCommandContext) async throws { await recorder.append("cursor-login") }
    func cursorStatus(context: TokscaleCommandContext) async throws -> CursorSessionStatus {
        await recorder.append("cursor-status")
        return await withCheckedContinuation { continuation in
            statusContinuation = continuation
            arrivalContinuation?.resume()
            arrivalContinuation = nil
        }
    }
    func waitForCursorStatus() async {
        if statusContinuation != nil { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }
    func resolveCursorStatus(_ status: CursorSessionStatus) {
        statusContinuation?.resume(returning: status)
        statusContinuation = nil
    }
    func submit(context: TokscaleCommandContext) async throws { await recorder.append("submit") }
    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        await recorder.append("status")
        return try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false}"#.utf8))
    }
    func configureAutosubmit(_ configuration: AutosubmitConfiguration, context: TokscaleCommandContext) async throws {}
    func disableAutosubmit(context: TokscaleCommandContext) async throws {}
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {}
}

private actor ContextChangingCursorStatusCLI: TokscaleCLIService {
    private let recorder: EventRecorder
    private var firstContinuation: CheckedContinuation<CursorSessionStatus, Never>?
    private var firstArrival: CheckedContinuation<Void, Never>?
    private var countArrivals: [(Int, CheckedContinuation<Void, Never>)] = []
    private var contexts: [TokscaleCommandContext] = []

    init(recorder: EventRecorder) { self.recorder = recorder }

    func whoAmI(context: TokscaleCommandContext) async throws -> String { "youranreus" }
    func loginCursor(context: TokscaleCommandContext) async throws {}
    func cursorStatus(context: TokscaleCommandContext) async throws -> CursorSessionStatus {
        contexts.append(context)
        await recorder.append("cursor-status")
        let count = contexts.count
        let ready = countArrivals.filter { count >= $0.0 }
        countArrivals.removeAll { count >= $0.0 }
        ready.forEach { $0.1.resume() }
        if count == 1 {
            return await withCheckedContinuation { continuation in
                firstContinuation = continuation
                firstArrival?.resume()
                firstArrival = nil
            }
        }
        return .unavailable
    }
    func waitForFirstCursorStatus() async {
        if firstContinuation != nil { return }
        await withCheckedContinuation { firstArrival = $0 }
    }
    func waitForCursorStatusCount(_ expected: Int) async {
        if contexts.count >= expected { return }
        await withCheckedContinuation { countArrivals.append((expected, $0)) }
    }
    func resolveFirstCursorStatus(_ status: CursorSessionStatus) {
        firstContinuation?.resume(returning: status)
        firstContinuation = nil
    }
    func cursorContexts() -> [TokscaleCommandContext] { contexts }
    func submit(context: TokscaleCommandContext) async throws {}
    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        await recorder.append("status")
        return try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false}"#.utf8))
    }
    func configureAutosubmit(_ configuration: AutosubmitConfiguration, context: TokscaleCommandContext) async throws {}
    func disableAutosubmit(context: TokscaleCommandContext) async throws {}
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {}
}

private actor ControlledStatusCLI: TokscaleCLIService {
    private var statusContinuation: CheckedContinuation<AutosubmitStatus, Error>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var statusRequested = false

    func whoAmI(context: TokscaleCommandContext) async throws -> String { "youranreus" }
    func loginCursor(context: TokscaleCommandContext) async throws {}
    func cursorStatus(context: TokscaleCommandContext) async throws -> CursorSessionStatus { .valid }
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
    func loginCursor(context: TokscaleCommandContext) async throws {}
    func cursorStatus(context: TokscaleCommandContext) async throws -> CursorSessionStatus { .valid }

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

private actor SuspendedMutationCLI: TokscaleCLIService {
    enum Kind { case configure, run }

    private let recorder: EventRecorder
    private let kind: Kind
    private var mutationContinuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var mutationStarted = false
    private var recordedStatusContexts: [TokscaleCommandContext] = []

    init(recorder: EventRecorder, kind: Kind) {
        self.recorder = recorder
        self.kind = kind
    }

    func whoAmI(context: TokscaleCommandContext) async throws -> String { "youranreus" }
    func loginCursor(context: TokscaleCommandContext) async throws {}
    func cursorStatus(context: TokscaleCommandContext) async throws -> CursorSessionStatus { .valid }
    func submit(context: TokscaleCommandContext) async throws {}
    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        await recorder.append("status")
        recordedStatusContexts.append(context)
        return try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false}"#.utf8))
    }

    func configureAutosubmit(
        _ configuration: AutosubmitConfiguration,
        context: TokscaleCommandContext
    ) async throws {
        guard kind == .configure else { return }
        await recorder.append("configure")
        await suspendMutation()
    }

    func disableAutosubmit(context: TokscaleCommandContext) async throws {}

    func runAutosubmitNow(context: TokscaleCommandContext) async throws {
        guard kind == .run else { return }
        await recorder.append("run")
        await suspendMutation()
    }

    func waitForMutation() async {
        if mutationStarted { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func resumeMutation() {
        mutationContinuation?.resume()
        mutationContinuation = nil
    }

    func statusContexts() -> [TokscaleCommandContext] { recordedStatusContexts }

    private func suspendMutation() async {
        mutationStarted = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        await withCheckedContinuation { mutationContinuation = $0 }
    }
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
    private var sleeps = 0

    func sleep(_ nanoseconds: UInt64) async {
        await withCheckedContinuation { continuation in
            latestNanoseconds = nanoseconds
            sleeps += 1
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

    func sleepCount() -> Int { sleeps }
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

private struct MissingNpxLocator: NpxLocating {
    func locate(preferredPath: String?) -> URL? { nil }
}

private final class InMemoryCache: DashboardCacheStoring {
    var snapshot: DashboardCacheSnapshot?
    private(set) var saveCount = 0
    let saveError: Error?

    init(snapshot: DashboardCacheSnapshot? = nil, saveError: Error? = nil) {
        self.snapshot = snapshot
        self.saveError = saveError
    }
    func load() -> DashboardCacheSnapshot? { snapshot }
    func save(_ snapshot: DashboardCacheSnapshot) throws {
        saveCount += 1
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

private actor ToggleableBatchAPI: TokscaleAPIService {
    private let recorder: EventRecorder
    private var isFailing: Bool

    init(recorder: EventRecorder, isFailing: Bool) {
        self.recorder = recorder
        self.isFailing = isFailing
    }

    func setFailing(_ value: Bool) { isFailing = value }

    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch {
        await recorder.append("fetch")
        if isFailing { throw TestFailure.unavailable }
        return try makeBatch(username: username)
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
