import XCTest
@testable import TokChan

@MainActor
final class DiscoveryRaceTests: XCTestCase {
    func testSettingsContextWinsWhenExplicitDiscoveryResumes() async throws {
        try await checkSavedContext(discoveryFails: false)
    }

    func testSettingsContextWinsWhenExplicitDiscoveryFails() async throws {
        try await checkSavedContext(discoveryFails: true)
    }

    func testCLIContextOnlyChangeSupersedesSuccessfulExplicitDiscovery() async {
        let cli = DiscoveryCLI()
        let preferences = DiscoveryPreferences()
        let model = DashboardViewModel(
            api: DiscoveryAPI(),
            cli: cli,
            preferencesStore: preferences,
            npxLocator: DiscoveryLocator(),
            cacheStore: DiscoveryCache()
        )
        let discovery = Task { await model.discoverIdentity() }
        await cli.waitForDiscovery()

        let updated = UserPreferences(username: "", tokscaleVersion: "4.15.0", npxPath: "/new/npx")
        model.updatePreferences(updated)
        await cli.finishDiscovery(fails: false)
        await discovery.value

        XCTAssertEqual(model.preferences, updated)
        XCTAssertEqual(model.firstUseOnboardingState, .usernameEntry(
            message: "Tokscale 命令设置已变化，请重新识别本机登录。"
        ))
        XCTAssertNil(model.profileState.loadedValue)
        let discoveryCount = await cli.discoveryCount()
        XCTAssertEqual(discoveryCount, 1)
    }

    func testSettingsAccountWinsWhenExplicitDiscoveryFails() async {
        let cli = DiscoveryCLI()
        let model = DashboardViewModel(
            api: DiscoveryAPI(totalTokens: 0),
            cli: cli,
            preferencesStore: DiscoveryPreferences(),
            npxLocator: DiscoveryLocator(),
            cacheStore: DiscoveryCache()
        )
        let discovery = Task { await model.discoverIdentity() }
        await cli.waitForDiscovery()

        model.updatePreferences(
            UserPreferences(username: "youranreus", tokscaleVersion: "4.15.0", npxPath: "/new/npx")
        )
        await cli.finishDiscovery(fails: true)
        await discovery.value

        XCTAssertEqual(model.firstUseOnboardingState, .verifying(username: "youranreus"))
        XCTAssertNil(model.profileState.loadedValue)
        let discoveryCount = await cli.discoveryCount()
        XCTAssertEqual(discoveryCount, 1)
    }

    func testDuplicateExplicitDiscoveryStartsOneWhoami() async {
        let cli = DiscoveryCLI()
        let model = DashboardViewModel(
            api: DiscoveryAPI(),
            cli: cli,
            preferencesStore: DiscoveryPreferences(),
            npxLocator: DiscoveryLocator(),
            cacheStore: DiscoveryCache()
        )
        let discovery = Task { await model.discoverIdentity() }
        await cli.waitForDiscovery()

        await model.discoverIdentity()
        let discoveryCount = await cli.discoveryCount()
        XCTAssertEqual(discoveryCount, 1)

        await cli.finishDiscovery(fails: true)
        await discovery.value
        guard case .usernameEntry(message: .some) = model.firstUseOnboardingState else {
            return XCTFail("Expected retryable username entry")
        }
    }

    private func checkSavedContext(discoveryFails: Bool) async throws {
        let cli = DiscoveryCLI()
        let preferences = DiscoveryPreferences()
        let model = DashboardViewModel(
            api: DiscoveryAPI(), cli: cli, preferencesStore: preferences,
            npxLocator: DiscoveryLocator(), cacheStore: DiscoveryCache())
        let discovery = Task { await model.discoverIdentity() }
        await cli.waitForDiscovery()

        let updated = UserPreferences(
            username: "youranreus",
            tokscaleVersion: "4.15.0",
            npxPath: "/new/npx"
        )
        model.updatePreferences(updated)

        await cli.finishDiscovery(fails: discoveryFails)
        await discovery.value

        XCTAssertEqual(model.preferences, updated)
        XCTAssertNil(model.profileState.loadedValue)
        XCTAssertEqual(model.firstUseOnboardingState, .verifying(username: "youranreus"))
        let discoveryCount = await cli.discoveryCount()
        XCTAssertEqual(discoveryCount, 1)
    }
}

private actor DiscoveryCLI: TokscaleCLIService {
    private var discovery: CheckedContinuation<String, Error>?
    private var arrival: CheckedContinuation<Void, Never>?
    private var discoveries = 0

    func whoAmI(context: TokscaleCommandContext) async throws -> String {
        discoveries += 1
        return try await withCheckedThrowingContinuation { continuation in
            discovery = continuation
            arrival?.resume()
            arrival = nil
        }
    }

    func waitForDiscovery() async {
        if discovery != nil { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func finishDiscovery(fails: Bool) {
        if fails {
            discovery?.resume(throwing: TokscaleCLIError.failed(exitCode: 1, message: "old discovery failed"))
        } else {
            discovery?.resume(returning: "old-account")
        }
        discovery = nil
    }

    func discoveryCount() -> Int { discoveries }
    func loginCursor(context: TokscaleCommandContext) async throws {}
    func cursorStatus(context: TokscaleCommandContext) async throws -> CursorSessionStatus { .valid }
    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false}"#.utf8))
    }
    func submit(context: TokscaleCommandContext) async throws {}
    func configureAutosubmit(_ configuration: AutosubmitConfiguration, context: TokscaleCommandContext) async throws {}
    func disableAutosubmit(context: TokscaleCommandContext) async throws {}
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {}
}

private struct DiscoveryAPI: TokscaleAPIService {
    var totalTokens: Double?

    init(totalTokens: Double? = nil) {
        self.totalTokens = totalTokens
    }

    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch {
        var profiles: [ProfilePeriod: DashboardData] = [:]
        for period in ProfilePeriod.allCases {
            var json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(ProfileModelsTests.profileJSON.utf8)) as? [String: Any]
            )
            json["period"] = period.rawValue
            var user = try XCTUnwrap(json["user"] as? [String: Any])
            user["username"] = username
            json["user"] = user
            if let totalTokens {
                var stats = try XCTUnwrap(json["stats"] as? [String: Any])
                stats["totalTokens"] = totalTokens
                json["stats"] = stats
            }
            let response = try JSONDecoder().decode(
                PublicProfileResponse.self,
                from: JSONSerialization.data(withJSONObject: json)
            )
            profiles[period] = DashboardData(response: response)
        }
        return try DashboardProfileBatch(username: username, profiles: profiles)
    }
}

private final class DiscoveryPreferences: PreferencesStoring {
    private var value = UserPreferences(username: "", tokscaleVersion: "latest", npxPath: "/old/npx")
    func load() -> UserPreferences { value }
    func save(_ preferences: UserPreferences) { value = preferences }
}

private struct DiscoveryLocator: NpxLocating {
    func locate(preferredPath: String?) -> URL? {
        preferredPath.map { URL(fileURLWithPath: $0) }
    }
}

private final class DiscoveryCache: DashboardCacheStoring {
    func load() -> DashboardCacheSnapshot? { nil }
    func save(_ snapshot: DashboardCacheSnapshot) throws {}
}
