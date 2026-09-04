import Foundation
import XCTest
@testable import TokChan

@MainActor
final class NpxSettingsTests: XCTestCase {
    func testEmptyOverridePresentsAutomaticDetectionCollapsed() {
        let detected = URL(fileURLWithPath: "/opt/homebrew/bin/npx")
        let viewModel = makeViewModel(locator: FixedNpxLocator(result: detected))

        let status = viewModel.npxPathStatus(for: "")

        XCTAssertEqual(status, .automatic(detected))
        XCTAssertFalse(status.shouldExpandOverride)
    }

    func testValidOverridePresentsCustomPathExpanded() {
        let custom = URL(fileURLWithPath: "/custom/bin/npx")
        let viewModel = makeViewModel(locator: FixedNpxLocator(result: custom))

        let status = viewModel.npxPathStatus(for: "  /custom/bin/npx  ")

        XCTAssertEqual(status, .custom(custom))
        XCTAssertTrue(status.shouldExpandOverride)
    }

    func testInvalidOverridePresentsAutomaticFallbackExpanded() {
        let fallback = URL(fileURLWithPath: "/usr/local/bin/npx")
        let viewModel = makeViewModel(locator: FixedNpxLocator(result: fallback))

        let status = viewModel.npxPathStatus(for: "/missing/npx")

        XCTAssertEqual(status, .automaticFallback(fallback))
        XCTAssertTrue(status.shouldExpandOverride)
    }

    func testMissingDetectionPresentsRecoveryControlsExpanded() {
        let viewModel = makeViewModel(locator: FixedNpxLocator(result: nil))

        let status = viewModel.npxPathStatus(for: "")

        XCTAssertEqual(status, .unavailable)
        XCTAssertTrue(status.shouldExpandOverride)
    }

    private func makeViewModel(locator: NpxLocating) -> DashboardViewModel {
        DashboardViewModel(
            api: PreviewAPIService(),
            cli: PreviewCLIService(),
            preferencesStore: PreviewPreferencesStore(),
            npxLocator: locator,
            cacheStore: PreviewCacheStore()
        )
    }
}

private struct FixedNpxLocator: NpxLocating {
    let result: URL?

    func locate(preferredPath: String?) -> URL? { result }
}
