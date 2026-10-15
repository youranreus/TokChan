import XCTest
@testable import TokChan

@MainActor
final class PreSubmitCursorSyncTests: XCTestCase {
    private enum Entry: CaseIterable {
        case first, manual, panel, run
        func perform(_ model: DashboardViewModel) async {
            switch self {
            case .first: await model.submitFirstUsage()
            case .manual: await model.submitUsageAndRefreshStatistics()
            case .panel: await model.refreshCurrentSourceFromPanel()
            case .run: await model.runAutosubmitNow()
            }
        }
        var upload: String { self == .run ? "run" : "submit" }
    }

    func testDefaultOffPreservesEveryOriginalSequence() async throws {
        for entry in Entry.allCases {
            let fixture = try makeFixture(entry: entry, enabled: false)
            await entry.perform(fixture.model)
            let events = await fixture.services.events
            XCTAssertEqual(events.first, entry.upload)
            XCTAssertEqual(events.filter { $0 == "fetch" }.count, 1)
            XCTAssertEqual(events.count, entry == .run ? 3 : 2)
            XCTAssertFalse(events.contains("sync"))
        }
    }

    func testEnabledOrdersOneSyncThenUploadThenOriginalReadsWithSameConfiguredContext() async throws {
        for entry in Entry.allCases {
            let fixture = try makeFixture(entry: entry)
            await entry.perform(fixture.model)
            let events = await fixture.services.events
            XCTAssertEqual(Array(events.prefix(2)), ["sync", entry.upload])
            XCTAssertEqual(events.filter { $0 == "fetch" }.count, 1)
            XCTAssertEqual(events.filter { $0 == "status" }.count, entry == .run ? 1 : 0)
            let contexts = await fixture.services.uploadContexts
            XCTAssertEqual(contexts.map(\.version), ["4.15.0", "4.15.0"])
            XCTAssertEqual(contexts.map(\.npxURL.path), ["/fixture/node/bin/npx", "/fixture/node/bin/npx"])
        }
    }

    func testLocalModeOnlineMenuUploadStillSyncsAndLeavesLocalProjectionUnchanged() async throws {
        let fixture = try makeFixture(entry: .manual, mode: .local)
        let original = fixture.model.profileState.loadedValue
        await fixture.model.submitUsageAndRefreshStatistics()
        let events = await fixture.services.events
        XCTAssertEqual(events, ["sync", "submit", "fetch"])
        XCTAssertEqual(fixture.model.preferences.dataMode, .local)
        XCTAssertEqual(fixture.model.profileState.loadedValue, original)
    }

    func testFailuresBlockAllUploadsAndReadsPreserveCacheAndAllowRetry() async throws {
        let failures: [Error] = [
            TokscaleCLIError.failed(exitCode: 2, message: "unsupported command"),
            ProcessRunnerError.timedOut,
            TokscaleCLIError.cursorSyncFailed,
            TokscaleCLIError.invalidCursorSyncResult
        ]
        for entry in Entry.allCases {
            for error in failures {
                let fixture = try makeFixture(entry: entry, failure: error)
                let oldProfile = fixture.model.profileState.loadedValue
                let oldFreshness = fixture.model.cacheSavedAt
                let oldStatusTime = fixture.model.autosubmitObservedAt
                await entry.perform(fixture.model)
                let events = await fixture.services.events
                XCTAssertEqual(events, ["sync"])
                XCTAssertEqual(fixture.model.profileState.loadedValue, oldProfile)
                XCTAssertEqual(fixture.model.cacheSavedAt, oldFreshness)
                XCTAssertEqual(fixture.model.autosubmitObservedAt, oldStatusTime)
                XCTAssertEqual(fixture.cache.saves, 0)
                if entry == .first {
                    guard case let .firstSubmission(_, message) = fixture.model.firstUseOnboardingState else {
                        return XCTFail("First submission must remain retryable")
                    }
                    XCTAssertTrue(message?.contains("Cursor 同步失败，未提交用量") == true)
                    XCTAssertTrue(message?.contains("重试") == true)
                } else {
                    guard case let .failed(message) = fixture.model.operation else {
                        return XCTFail("Expected actionable failure")
                    }
                    XCTAssertTrue(message.contains("Cursor 同步失败，未提交用量"))
                    XCTAssertTrue(message.contains("重试"))
                    if entry != .run { XCTAssertNotNil(fixture.model.submitErrorMessage) }
                }
                await fixture.services.setFailure(nil)
                await entry.perform(fixture.model)
                let retried = await fixture.services.events
                XCTAssertEqual(Array(retried.prefix(3)), ["sync", "sync", entry.upload])
                XCTAssertEqual(retried.filter { $0 == entry.upload }.count, 1)
            }
        }
    }

    func testSuspendedSyncKeepsOneBusyLifetimeAndExcludesConflictingActions() async throws {
        for entry in Entry.allCases {
            let fixture = try makeFixture(entry: entry, suspended: true)
            let operation = Task { await entry.perform(fixture.model) }
            await fixture.services.waitForSync()
            XCTAssertEqual(fixture.model.operation, entry == .run ? .runningAutosubmit : .submitting)
            XCTAssertTrue(fixture.model.isPerformingOperation)
            for duplicate in Entry.allCases { await duplicate.perform(fixture.model) }
            await fixture.model.loginCursor()
            await fixture.model.refreshStatisticsNow()
            let applied = await fixture.model.applyAutosubmit(configuration)
            XCTAssertFalse(applied)
            await fixture.model.selectDataMode(.local)
            let events = await fixture.services.events
            XCTAssertEqual(events, ["sync"])
            XCTAssertEqual(fixture.model.preferences.dataMode, .online)
            await fixture.services.finishSync()
            await operation.value
            let final = await fixture.services.events
            XCTAssertEqual(Array(final.prefix(2)), ["sync", entry.upload])
            XCTAssertFalse(fixture.model.isPerformingOperation)
        }
    }

    func testAccountAndCLIChangesDuringSyncSupersedeSuccessAndLateFailure() async throws {
        for entry in Entry.allCases {
            for change in ["account", "version", "npx", "round-trip"] {
                for fails in [false, true] {
                    let fixture = try makeFixture(entry: entry, suspended: true)
                    let operation = Task { await entry.perform(fixture.model) }
                    await fixture.services.waitForSync()
                    let original = fixture.model.preferences
                    var updated = original
                    switch change {
                    case "account": updated.username = "replacement"
                    case "version": updated.tokscaleVersion = "4.16.0"
                    case "npx": updated.npxPath = "/fixture/other/bin/npx"
                    default: updated.username = "temporary"
                    }
                    fixture.model.updatePreferences(updated)
                    if change == "round-trip" { fixture.model.updatePreferences(original) }
                    await fixture.services.setFailure(fails ? TokscaleCLIError.cursorSyncFailed : nil)
                    await fixture.services.finishSync()
                    await operation.value
                    let events = await fixture.services.events
                    XCTAssertFalse(events.contains("submit"))
                    XCTAssertFalse(events.contains("run"))
                    XCTAssertFalse(events.contains("fetch"))
                    XCTAssertNil(fixture.model.submitErrorMessage)
                    XCTAssertEqual(fixture.model.operation, .idle)
                    if entry == .first, change == "version" || change == "npx" {
                        XCTAssertEqual(fixture.model.firstUseOnboardingState,
                                       .firstSubmission(username: original.username, message: nil))
                    }
                }
            }
        }
    }

    func testCancellationCannotUploadEvenIfSyncIgnoresCancellation() async throws {
        for entry in Entry.allCases {
            let fixture = try makeFixture(entry: entry, suspended: true)
            let operation = Task { await entry.perform(fixture.model) }
            await fixture.services.waitForSync()
            operation.cancel()
            await fixture.services.finishSync()
            await operation.value
            let events = await fixture.services.events
            XCTAssertEqual(events, ["sync"])
            XCTAssertEqual(fixture.model.operation, .idle)
            XCTAssertNil(fixture.model.submitErrorMessage)
        }
    }

    func testThrownCancellationStopsWithoutFailurePublication() async throws {
        for entry in Entry.allCases {
            let fixture = try makeFixture(entry: entry, failure: CancellationError())
            await entry.perform(fixture.model)
            let events = await fixture.services.events
            XCTAssertEqual(events, ["sync"])
            XCTAssertEqual(fixture.model.operation, .idle)
        }
    }

    func testClosingPopoverDuringSyncContinuesWorkAndSuppressesReopenedBanner() async throws {
        for fails in [false, true] {
            let fixture = try makeFixture(entry: .manual, suspended: true,
                                          failure: fails ? TokscaleCLIError.cursorSyncFailed : nil)
            fixture.model.panelDidAppear()
            let operation = Task { await fixture.model.submitUsageAndRefreshStatistics() }
            await fixture.services.waitForSync()
            fixture.model.panelDidDisappear()
            fixture.model.panelDidAppear()
            XCTAssertTrue(fixture.model.isPerformingOperation)
            await fixture.services.finishSync()
            await operation.value
            let events = await fixture.services.events
            XCTAssertEqual(events, fails ? ["sync"] : ["sync", "submit", "fetch"])
            XCTAssertEqual(fixture.model.dashboardOperation, .idle)
            if fails { XCTAssertNotNil(fixture.model.submitErrorMessage) }
        }
    }

    func testPreferenceIsCapturedOnceAndSavingIsLocalImmediateAndNormalized() async throws {
        let fixture = try makeFixture(entry: .manual, suspended: true)
        let operation = Task { await fixture.model.submitUsageAndRefreshStatistics() }
        await fixture.services.waitForSync()
        var updated = fixture.model.preferences
        updated.syncCursorBeforeSubmit = false
        fixture.model.updatePreferences(updated)
        XCTAssertFalse(fixture.store.load().syncCursorBeforeSubmit)
        await fixture.services.finishSync()
        await operation.value
        let first = await fixture.services.events
        XCTAssertEqual(first, ["sync", "submit", "fetch"])
        await fixture.model.submitUsageAndRefreshStatistics()
        let second = await fixture.services.events
        XCTAssertEqual(second, ["sync", "submit", "fetch", "submit", "fetch"])

        let local = try makeFixture(entry: .manual, enabled: false)
        var normalized = local.model.preferences
        normalized.username = "  youranreus  "
        normalized.syncCursorBeforeSubmit = true
        local.model.updatePreferences(normalized)
        XCTAssertTrue(local.store.load().syncCursorBeforeSubmit)
        XCTAssertEqual(local.store.load().username, "youranreus")
        let events = await local.services.events
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(local.cache.saves, 0)
    }

    func testValidatedZeroRowJSONContinuesAndPartialAccountJSONBlocksEveryEntry() async throws {
        for entry in Entry.allCases {
            for succeeds in [false, true] {
                let json = succeeds ? #"{"synced":true,"rows":0,"error":null}"#
                    : #"{"synced":true,"rows":7046,"error":"partial account failure"}"#
                let fixture = try makeFixture(entry: entry, syncJSON: json)
                await entry.perform(fixture.model)
                let events = await fixture.services.events
                if succeeds {
                    XCTAssertEqual(Array(events.prefix(2)), ["sync", entry.upload])
                    XCTAssertEqual(events.filter { $0 == "fetch" }.count, 1)
                } else {
                    XCTAssertEqual(events, ["sync"])
                    XCTAssertEqual(fixture.cache.saves, 0)
                }
            }
        }
    }

    func testRunNowSyncsEvenWhenConfiguredAutosubmitClientsExcludeCursor() async throws {
        let fixture = try makeFixture(entry: .run)
        let applied = await fixture.model.applyAutosubmit(configuration)
        XCTAssertTrue(applied)
        await fixture.model.runAutosubmitNow()
        let events = await fixture.services.events
        XCTAssertEqual(Array(events.prefix(4)), ["configure", "status", "sync", "run"])
        XCTAssertEqual(events.filter { $0 == "sync" }.count, 1)
    }

    func testInvalidVersionAndMissingNpxAreContextualizedWithoutStartingAnyCommand() async throws {
        for entry in Entry.allCases {
            for missingNpx in [false, true] {
                let fixture = try makeFixture(entry: entry, version: missingNpx ? "latest" : "latest;rm",
                                              npxAvailable: !missingNpx)
                await entry.perform(fixture.model)
                let events = await fixture.services.events
                XCTAssertTrue(events.isEmpty)
                XCTAssertEqual(fixture.cache.saves, 0)
                let message: String
                if entry == .first, case let .firstSubmission(_, feedback) = fixture.model.firstUseOnboardingState {
                    message = feedback ?? ""
                } else if case let .failed(feedback) = fixture.model.operation {
                    message = feedback
                } else { return XCTFail("Expected retryable preflight feedback") }
                XCTAssertTrue(message.contains("Cursor 同步失败，未提交用量"))
                XCTAssertTrue(message.contains(missingNpx ? "找不到 npx" : "语义化版本号"))
            }
        }
    }

    func testAlreadyCancelledActionDoesNotStartSyncOrUpload() async throws {
        for entry in Entry.allCases {
            let fixture = try makeFixture(entry: entry)
            let operation = Task { await entry.perform(fixture.model) }
            operation.cancel()
            await operation.value
            let events = await fixture.services.events
            XCTAssertTrue(events.isEmpty)
            XCTAssertEqual(fixture.model.operation, .idle)
        }
    }

    func testResetRestoresDefaultOff() async throws {
        let fixture = try makeFixture(entry: .manual)
        let succeeded = await fixture.model.resetConfiguration(disableLaunchAtLogin: {})
        XCTAssertTrue(succeeded)
        XCTAssertFalse(fixture.model.preferences.syncCursorBeforeSubmit)
        XCTAssertFalse(fixture.store.load().syncCursorBeforeSubmit)
        let events = await fixture.services.events
        XCTAssertTrue(events.isEmpty)
    }

    func testReadOnlyAutomaticLoginAndAutosubmitConfigurationNeverPreflightEvenWhenEnabled() async throws {
        let fixture = try makeFixture(entry: .manual)
        await fixture.model.load()
        await fixture.model.reevaluateStatisticsAfterWake()
        await fixture.model.refreshStatisticsNow()
        await fixture.model.loginCursor()
        await fixture.model.refreshAutosubmitStatus()
        var configuration = self.configuration
        configuration.enabled = true
        configuration.clients = ["codex"] // Cursor excluded does not influence the policy.
        _ = await fixture.model.applyAutosubmit(configuration)
        configuration.enabled = false
        _ = await fixture.model.applyAutosubmit(configuration)
        let events = await fixture.services.events
        XCTAssertFalse(events.contains("sync"))
        XCTAssertFalse(events.contains("submit"))
        XCTAssertFalse(events.contains("run"))
        XCTAssertTrue(events.contains("login"))
        XCTAssertTrue(events.contains("configure"))
        XCTAssertTrue(events.contains("disable"))

        let local = try makeFixture(entry: .manual, mode: .local)
        await local.model.refreshCurrentSourceFromPanel()
        let localEvents = await local.services.events
        XCTAssertEqual(localEvents, ["local"])
    }

    private var configuration: AutosubmitConfiguration {
        AutosubmitConfiguration(enabled: true, intervalMinutes: 120, clients: ["codex"],
                                filterKind: .all, year: "", since: "", until: "")
    }

    private func makeFixture(entry: Entry, enabled: Bool = true, mode: DashboardDataMode = .online,
                             suspended: Bool = false, failure: Error? = nil, syncJSON: String? = nil,
                             version: String = "4.15.0", npxAvailable: Bool = true) throws -> Fixture {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let preferences = UserPreferences(username: "youranreus", tokscaleVersion: version,
                                          npxPath: "/fixture/node/bin/npx", dataMode: mode,
                                          syncCursorBeforeSubmit: enabled)
        let store = SyncPreferences(preferences)
        let services = PreSubmitServices(suspended: suspended, failure: failure)
        let batch = try syncTestBatch(username: preferences.username, tokens: entry == .first ? 0 : 42)
        let entries = DashboardDataMode.allCases.flatMap { source in
            batch.profiles.values.map { CachedDashboardProfile(data: $0, savedAt: date, source: source) }
        }
        let cache = SyncCache(DashboardCacheSnapshot(
            profile: batch.profiles[.all], autosubmit: nil, savedAt: date,
            profiles: entries, username: preferences.username, fetchedAt: date,
            fetchedAtBySource: [.online: date, .local: date]
        ))
        let cli: TokscaleCLIService = syncJSON.map {
            TokscaleCLIClient(runner: PreSubmitJSONRunner(services: services, syncJSON: $0))
        } ?? services
        let model = DashboardViewModel(api: services, cli: cli, localDataSource: services,
                                       preferencesStore: store, npxLocator: SyncNpxLocator(available: npxAvailable),
                                       cacheStore: cache,
                                       now: { date })
        return Fixture(model: model, services: services, store: store, cache: cache)
    }

    private struct Fixture {
        let model: DashboardViewModel
        let services: PreSubmitServices
        let store: SyncPreferences
        let cache: SyncCache
    }
}

private actor PreSubmitServices: TokscaleCLIService, TokscaleAPIService, DashboardDataReading {
    nonisolated let source = DashboardDataMode.local
    private(set) var events: [String] = []
    private(set) var uploadContexts: [TokscaleCommandContext] = []
    private var suspended: Bool
    private var failure: Error?
    private var syncContinuation: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    init(suspended: Bool, failure: Error?) { self.suspended = suspended; self.failure = failure }
    func syncCursor(context: TokscaleCommandContext) async throws {
        events.append("sync")
        uploadContexts.append(context)
        if suspended {
            await withCheckedContinuation { continuation in
                syncContinuation = continuation
                arrival?.resume()
                arrival = nil
            }
        }
        if let failure { throw failure }
    }
    func waitForSync() async {
        if syncContinuation != nil { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func finishSync() { suspended = false; syncContinuation?.resume(); syncContinuation = nil }
    func setFailure(_ error: Error?) { failure = error }
    func record(_ event: String) { events.append(event) }
    func submit(context: TokscaleCommandContext) async throws {
        events.append("submit"); uploadContexts.append(context)
    }
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {
        events.append("run"); uploadContexts.append(context)
    }
    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch {
        events.append("fetch")
        return try syncTestBatch(username: username, tokens: 99)
    }
    func fetchDashboardBatch(_ request: DashboardSourceRequest) async throws -> DashboardSourceBatch {
        events.append("local")
        return try DashboardSourceBatch(source: .local, account: nil,
                                         profiles: syncTestBatch(username: "local", tokens: 7).profiles)
    }
    func whoAmI(context: TokscaleCommandContext) async throws -> String { events.append("whoami"); return "youranreus" }
    func loginCursor(context: TokscaleCommandContext) async throws { events.append("login") }
    func cursorStatus(context: TokscaleCommandContext) async throws -> CursorSessionStatus {
        events.append("cursor-status"); return .valid
    }
    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        events.append("status")
        return try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false}"#.utf8))
    }
    func configureAutosubmit(_ configuration: AutosubmitConfiguration, context: TokscaleCommandContext) async throws {
        events.append("configure")
    }
    func disableAutosubmit(context: TokscaleCommandContext) async throws { events.append("disable") }
}

private func syncTestBatch(username: String, tokens: Double) throws -> DashboardProfileBatch {
    var profiles: [ProfilePeriod: DashboardData] = [:]
    for period in ProfilePeriod.allCases {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ProfileModelsTests.profileJSON.utf8)) as? [String: Any])
        json["period"] = period.rawValue
        var user = try XCTUnwrap(json["user"] as? [String: Any])
        user["username"] = username
        json["user"] = user
        var stats = try XCTUnwrap(json["stats"] as? [String: Any])
        stats["totalTokens"] = tokens
        json["stats"] = stats
        let response = try JSONDecoder().decode(PublicProfileResponse.self, from: JSONSerialization.data(withJSONObject: json))
        profiles[period] = DashboardData(response: response)
    }
    return try DashboardProfileBatch(username: username, profiles: profiles)
}

private final class SyncPreferences: PreferencesStoring {
    var value: UserPreferences
    init(_ value: UserPreferences) { self.value = value }
    func load() -> UserPreferences { value }
    func save(_ preferences: UserPreferences) { value = preferences }
    func clear() throws { value = .defaults }
}

private final class SyncCache: DashboardCacheStoring {
    private let snapshot: DashboardCacheSnapshot
    private(set) var saves = 0
    init(_ snapshot: DashboardCacheSnapshot) { self.snapshot = snapshot }
    func load() -> DashboardCacheSnapshot? { snapshot }
    func save(_ snapshot: DashboardCacheSnapshot) throws { saves += 1 }
    func clear() throws {}
}

private struct PreSubmitJSONRunner: ProcessRunning {
    let services: PreSubmitServices
    let syncJSON: String
    func run(executable: URL, arguments: [String], environmentOverrides: [String: String],
             timeout: TimeInterval) async throws -> ProcessOutput {
        let suffix = Array(arguments.dropFirst(2))
        switch suffix {
        case ["cursor", "sync", "--json"]:
            await services.record("sync")
            return ProcessOutput(exitCode: 0, stdout: syncJSON, stderr: "")
        case ["submit"]:
            await services.record("submit")
        case ["autosubmit", "run", "--force"]:
            await services.record("run")
        case ["autosubmit", "status", "--json"]:
            await services.record("status")
            return ProcessOutput(exitCode: 0, stdout: #"{"enabled":false,"clients":["codex"]}"#, stderr: "")
        default:
            XCTFail("Unexpected command: \(suffix)")
            throw TokscaleCLIError.cursorSyncFailed
        }
        return ProcessOutput(exitCode: 0, stdout: "", stderr: "")
    }
}

private struct SyncNpxLocator: NpxLocating {
    var available = true
    func locate(preferredPath: String?) -> URL? {
        available ? URL(fileURLWithPath: preferredPath ?? "/fixture/node/bin/npx") : nil
    }
}
