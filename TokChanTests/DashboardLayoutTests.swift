import AppKit
import SwiftUI
import XCTest
@testable import TokChan

@MainActor
final class DashboardLayoutTests: XCTestCase {
    func testOnboardingAccountControlsUseOneLargeControlHeight() {
        XCTAssertEqual(FirstUseOnboardingView.accountControlHeight, 32)
    }

    func testRenderFixedDashboardInBothAppearances() async throws {
        let model = DashboardViewModel(api: PreviewAPIService(), cli: PreviewCLIService(),
            preferencesStore: PreviewPreferencesStore(), npxLocator: PreviewNpxLocator(),
            cacheStore: PreviewCacheStore())
        await model.load()
        let localModel = DashboardViewModel(
            api: PreviewAPIService(),
            cli: PreviewCLIService(),
            localDataSource: PreviewLocalDashboardDataSource(),
            preferencesStore: PreviewPreferencesStore(dataMode: .local),
            npxLocator: PreviewNpxLocator(),
            cacheStore: PreviewCacheStore()
        )
        await localModel.load()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            try render(model: model, appearance: appearance, outputName: "TokChan-dashboard-\(name)")
            try render(model: localModel, appearance: appearance, outputName: "TokChan-local-dashboard-\(name)")
        }
    }

    func testRenderBothOnboardingStepsAtFixedSizeInBothAppearances() async throws {
        let modeSelection = DashboardViewModel(
            api: PreviewAPIService(),
            cli: PreviewCLIService(),
            localDataSource: PreviewLocalDashboardDataSource(),
            preferencesStore: PreviewPreferencesStore(
                username: "existing-user",
                dataMode: .local,
                hasCompletedInitialization: false
            ),
            npxLocator: PreviewNpxLocator(),
            cacheStore: PreviewCacheStore()
        )
        XCTAssertEqual(modeSelection.firstUseOnboardingState, .modeSelection)

        let usernameEntry = DashboardViewModel(
            api: PreviewAPIService(),
            cli: PreviewCLIService(),
            preferencesStore: PreviewPreferencesStore(username: ""),
            npxLocator: PreviewNpxLocator(isAvailable: false),
            cacheStore: PreviewCacheStore()
        )
        await usernameEntry.load()
        guard case .usernameEntry = usernameEntry.firstUseOnboardingState else {
            return XCTFail("Expected username entry onboarding")
        }

        let firstSubmission = DashboardViewModel(
            api: PreviewAPIService(totalTokens: 0),
            cli: PreviewCLIService(),
            preferencesStore: PreviewPreferencesStore(),
            npxLocator: PreviewNpxLocator(),
            cacheStore: PreviewCacheStore()
        )
        await firstSubmission.load()
        guard case .firstSubmission = firstSubmission.firstUseOnboardingState else {
            return XCTFail("Expected first submission onboarding")
        }

        for (step, model) in [
            ("mode", modeSelection),
            ("username", usernameEntry),
            ("submission", firstSubmission)
        ] {
            for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                try render(
                    model: model,
                    appearance: appearance,
                    outputName: "TokChan-onboarding-\(step)-\(appearanceName)"
                )
            }
        }
    }

    func testRenderCursorLoginStatesInsideFixedOnboardingViewport() async throws {
        let idle = emptyOnboardingModel(cli: PreviewCLIService())

        let success = emptyOnboardingModel(cli: PreviewCLIService())
        await success.loginCursor()
        XCTAssertEqual(success.cursorLoginState, .succeeded("Cursor 登录成功。"))

        let failure = emptyOnboardingModel(cli: PreviewCLIService())
        var invalidPreferences = failure.preferences
        invalidPreferences.tokscaleVersion = "invalid"
        failure.updatePreferences(invalidPreferences)
        await failure.loginCursor()
        guard case .failed = failure.cursorLoginState else {
            return XCTFail("Expected failed Cursor login state")
        }

        let runningCLI = SuspendedLayoutCursorCLI()
        let running = emptyOnboardingModel(cli: runningCLI)
        let login = Task { await running.loginCursor() }
        await runningCLI.waitForLogin()
        XCTAssertEqual(running.cursorLoginState, .loggingIn)

        for (state, model) in [("idle", idle), ("success", success), ("failure", failure), ("running", running)] {
            for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                try render(
                    model: model,
                    appearance: appearance,
                    outputName: "TokChan-cursor-\(state)-\(appearanceName)"
                )
            }
        }

        await runningCLI.resumeLogin()
        await login.value
    }

    private func emptyOnboardingModel(cli: TokscaleCLIService) -> DashboardViewModel {
        DashboardViewModel(
            api: PreviewAPIService(),
            cli: cli,
            preferencesStore: PreviewPreferencesStore(username: ""),
            npxLocator: PreviewNpxLocator(),
            cacheStore: PreviewCacheStore()
        )
    }

    private func render(
        model: DashboardViewModel,
        appearance: NSAppearance.Name,
        outputName: String
    ) throws {
        let hosting = NSHostingView(rootView: DashboardView(viewModel: model)
            .environment(\.locale, Locale(identifier: "zh_CN")))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 680),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.appearance = NSAppearance(named: appearance)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 680)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/private/tmp/\(outputName).png"))
        XCTAssertEqual(hosting.fittingSize.width, 380, accuracy: 1)
        XCTAssertEqual(hosting.fittingSize.height, 680, accuracy: 1)
    }
}

private actor SuspendedLayoutCursorCLI: TokscaleCLIService {
    private var loginContinuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var loginStarted = false

    func whoAmI(context: TokscaleCommandContext) async throws -> String { "youranreus" }

    func loginCursor(context: TokscaleCommandContext) async throws {
        loginStarted = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        await withCheckedContinuation { loginContinuation = $0 }
    }

    func waitForLogin() async {
        if loginStarted { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func resumeLogin() {
        loginContinuation?.resume()
        loginContinuation = nil
    }

    func cursorStatus(context: TokscaleCommandContext) async throws -> CursorSessionStatus { .valid }
    func submit(context: TokscaleCommandContext) async throws {}
    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false}"#.utf8))
    }
    func configureAutosubmit(_ configuration: AutosubmitConfiguration, context: TokscaleCommandContext) async throws {}
    func disableAutosubmit(context: TokscaleCommandContext) async throws {}
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {}
}
