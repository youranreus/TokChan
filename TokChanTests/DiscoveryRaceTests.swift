import XCTest
@testable import TokChan

@MainActor
final class DiscoveryRaceTests: XCTestCase {
    func testSettingsContextWinsWhenInitialDiscoveryResumes() async throws {
        try await checkSavedContext(discoveryFails: false)
    }

    func testSettingsContextWinsWhenInitialDiscoveryFails() async throws {
        try await checkSavedContext(discoveryFails: true)
    }

    private func checkSavedContext(discoveryFails: Bool) async throws {
        let cli = DiscoveryCLI()
        let preferences = DiscoveryPreferences()
        let model = DashboardViewModel(
            api: DiscoveryAPI(), cli: cli, preferencesStore: preferences,
            npxLocator: DiscoveryLocator(), cacheStore: DiscoveryCache())
        let initialLoad = Task { await model.load() }
        await cli.waitForDiscovery()

        let updated = UserPreferences(username: "youranreus", tokscaleVersion: "4.15.0", npxPath: "/new/npx")
        let saved = await model.saveSettings(preferences: updated, autosubmit: AutosubmitConfiguration(
            enabled: false, intervalMinutes: 120, clients: [], filterKind: .all,
            year: "", since: "", until: ""))
        XCTAssertTrue(saved)

        await cli.finishDiscovery(fails: discoveryFails)
        await initialLoad.value

        let contexts = await cli.recordedStatusContexts()
        XCTAssertEqual(contexts.count, 1)
        let expected = TokscaleCommandContext(npxURL: URL(fileURLWithPath: "/new/npx"), version: "4.15.0")
        XCTAssertTrue(contexts.allSatisfy { $0 == expected })
        XCTAssertEqual(model.preferences, updated)
        XCTAssertNil(model.autosubmitLoadErrorMessage)
        XCTAssertEqual(model.profileState.loadedValue?.username, "youranreus")
    }
}

private actor DiscoveryCLI: TokscaleCLIService {
    private var discovery: CheckedContinuation<String, Error>?
    private var arrival: CheckedContinuation<Void, Never>?
    private var statusContexts: [TokscaleCommandContext] = []

    func whoAmI(context: TokscaleCommandContext) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
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
        if fails { discovery?.resume(throwing: TokscaleCLIError.failed(exitCode: 1, message: "old discovery failed")) }
        else { discovery?.resume(returning: "old-account") }
        discovery = nil
    }

    func recordedStatusContexts() -> [TokscaleCommandContext] { statusContexts }

    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        statusContexts.append(context)
        return try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false}"#.utf8))
    }

    func submit(context: TokscaleCommandContext) async throws {}
    func configureAutosubmit(_ configuration: AutosubmitConfiguration, context: TokscaleCommandContext) async throws {}
    func disableAutosubmit(context: TokscaleCommandContext) async throws {}
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {}
}

private struct DiscoveryAPI: TokscaleAPIService {
    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch {
        var profiles: [ProfilePeriod: DashboardData] = [:]
        for period in ProfilePeriod.allCases {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ProfileModelsTests.profileJSON.utf8)) as? [String: Any])
            json["period"] = period.rawValue
            var user = try XCTUnwrap(json["user"] as? [String: Any])
            user["username"] = username
            json["user"] = user
            let response = try JSONDecoder().decode(PublicProfileResponse.self, from: JSONSerialization.data(withJSONObject: json))
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
