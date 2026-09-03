import SwiftUI
import XCTest
@testable import TokChan

@MainActor
final class SettingsWindowActionTests: XCTestCase {
    func testDashboardUsesNativeSettingsLinkOnSupportedSystems() throws {
        guard #available(macOS 14.0, *) else {
            throw XCTSkip("macOS 13 uses the legacy settings action")
        }

        let view = DashboardView(
            viewModel: DashboardViewModel(
                api: PreviewAPIService(),
                cli: PreviewCLIService(),
                preferencesStore: PreviewPreferencesStore(),
                npxLocator: PreviewNpxLocator(),
                cacheStore: PreviewCacheStore()
            )
        )

        XCTAssertTrue(
            containsType(named: "SettingsLink", in: view.body),
            "The dashboard settings control must use SwiftUI.SettingsLink"
        )
    }

    private func containsType(named name: String, in value: Any) -> Bool {
        if String(reflecting: type(of: value)).contains(name) {
            return true
        }
        return Mirror(reflecting: value).children.contains { child in
            containsType(named: name, in: child.value)
        }
    }
}
