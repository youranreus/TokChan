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
            npxPath: "/opt/homebrew/bin/npx"
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
        XCTAssertNil(defaults.string(forKey: "apiToken"))
    }
}
