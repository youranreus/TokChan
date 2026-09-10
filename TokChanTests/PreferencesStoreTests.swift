import XCTest
@testable import TokChan

final class PreferencesStoreTests: XCTestCase {
    func testRoundTripUsesOnlyExpectedPreferences() throws {
        let suiteName = "TokChanTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let expected = UserPreferences(
            username: "youranreus",
            tokscaleVersion: "4.15.0",
            npxPath: "/opt/homebrew/bin/npx",
            dataMode: .local,
            hasCompletedInitialization: true,
            statusTextEnabled: true,
            statusTextTemplate: "今日 {token}，成本 {cost}",
            statusTextPeriod: .month,
            hideZeroCostModels: true,
            hiddenClientsEnabled: true,
            hiddenClientIDs: ["zed", "cursor", "codex"],
            defaultPeriod: .month
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
        XCTAssertEqual(defaults.stringArray(forKey: "hiddenClientIDs"), ["codex", "cursor", "zed"])
        XCTAssertEqual(defaults.string(forKey: "defaultPeriod"), "month")
        XCTAssertNil(defaults.string(forKey: "apiToken"))
    }

    func testMissingStatusTextKeysUseBackwardCompatibleDefaults() throws {
        let suiteName = "TokChanTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("existing-user", forKey: "username")

        let preferences = UserDefaultsPreferencesStore(defaults: defaults).load()

        XCTAssertEqual(preferences.username, "existing-user")
        XCTAssertEqual(preferences.dataMode, .local)
        XCTAssertFalse(preferences.hasCompletedInitialization)
        XCTAssertFalse(preferences.statusTextEnabled)
        XCTAssertEqual(preferences.statusTextTemplate, UserPreferences.defaultStatusTextTemplate)
        XCTAssertEqual(preferences.statusTextPeriod, .day)
        XCTAssertFalse(preferences.hideZeroCostModels)
        XCTAssertFalse(preferences.hiddenClientsEnabled)
        XCTAssertTrue(preferences.hiddenClientIDs.isEmpty)
        XCTAssertEqual(preferences.defaultPeriod, .day)
    }

    func testDefaultPeriodRoundTripAndStoreContract() throws {
        let suiteName = "TokChanTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)

        store.save(UserPreferences(
            username: "youranreus",
            tokscaleVersion: "latest",
            npxPath: "",
            defaultPeriod: .week
        ))
        XCTAssertEqual(defaults.string(forKey: "defaultPeriod"), "week")
        XCTAssertEqual(store.load().defaultPeriod, .week)

        try store.clear()
        XCTAssertNil(defaults.string(forKey: "defaultPeriod"))
        XCTAssertEqual(store.load().defaultPeriod, .day)
    }

    func testDefaultPeriodFallsBackToDayWhenMissingOrUnknown() throws {
        let suiteName = "TokChanTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.load().defaultPeriod, .day)

        defaults.set("quarter", forKey: "defaultPeriod")
        XCTAssertEqual(store.load().defaultPeriod, .day)

        defaults.set("all", forKey: "defaultPeriod")
        XCTAssertEqual(store.load().defaultPeriod, .all)
    }

    func testHiddenClientIDsAreTrimmedDeduplicatedAndEmptyValuesAreDropped() throws {
        let suiteName = "TokChanTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([" cursor ", "", "\n", "codex", "cursor"], forKey: "hiddenClientIDs")

        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let preferences = store.load()

        XCTAssertEqual(preferences.hiddenClientIDs, ["codex", "cursor"])
        store.save(preferences)
        XCTAssertEqual(defaults.stringArray(forKey: "hiddenClientIDs"), ["codex", "cursor"])
    }

    func testInvalidStatusTextPeriodFallsBackToDayWithoutChangingOtherValues() throws {
        let suiteName = "TokChanTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "statusTextEnabled")
        defaults.set("custom {token}", forKey: "statusTextTemplate")
        defaults.set("quarter", forKey: "statusTextPeriod")

        let preferences = UserDefaultsPreferencesStore(defaults: defaults).load()

        XCTAssertTrue(preferences.statusTextEnabled)
        XCTAssertEqual(preferences.statusTextTemplate, "custom {token}")
        XCTAssertEqual(preferences.statusTextPeriod, .day)
    }
}
