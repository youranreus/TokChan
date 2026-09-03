import SwiftUI
import XCTest
@testable import TokChan

@MainActor
final class SettingsWindowActionTests: XCTestCase {
    func testDashboardUsesNativeSettingsAction() {
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
            containsType(named: "Button", in: view.body),
            "The dashboard settings control must expose a native Settings action"
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
