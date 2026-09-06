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
            statusTextEnabled: true,
            statusTextTemplate: "今日 {token}，成本 {cost}",
            statusTextPeriod: .month
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
        XCTAssertNil(defaults.string(forKey: "apiToken"))
    }

    func testMissingStatusTextKeysUseBackwardCompatibleDefaults() throws {
        let suiteName = "TokChanTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("existing-user", forKey: "username")

        let preferences = UserDefaultsPreferencesStore(defaults: defaults).load()

        XCTAssertEqual(preferences.username, "existing-user")
        XCTAssertFalse(preferences.statusTextEnabled)
        XCTAssertEqual(preferences.statusTextTemplate, UserPreferences.defaultStatusTextTemplate)
        XCTAssertEqual(preferences.statusTextPeriod, .day)
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
