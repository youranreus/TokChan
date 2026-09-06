import XCTest
@testable import TokChan

@MainActor
final class OperationBannerLifecycleTests: XCTestCase {
    func testCompletedSuccessClearsWhenPanelCloses() async {
        let model = makeModel(cli: PreviewCLIService())
        model.panelDidAppear()

        await model.refresh()
        XCTAssertEqual(model.operation, .succeeded("用量已提交，全部范围已更新。"))
        XCTAssertEqual(model.dashboardOperation, model.operation)

        model.panelDidDisappear()
        XCTAssertEqual(model.operation, .idle)
        XCTAssertEqual(model.dashboardOperation, .idle)
    }

    func testCompletedResultClearsWhenPanelCloses() async {
        let model = makeModel(cli: FailingSubmitCLI())
        model.panelDidAppear()

        await model.refresh()
        guard case .failed = model.operation else { return XCTFail("Expected visible failure") }

        model.panelDidDisappear()
        XCTAssertEqual(model.operation, .idle)
    }

    func testClosingDuringOperationDoesNotCancelWorkAndSuppressesTerminalBanner() async {
        let cli = SuspendedSubmitCLI()
        let model = makeModel(cli: cli)
        model.panelDidAppear()

        let operation = Task { await model.refresh() }
        await cli.waitForSubmit()
        model.panelDidDisappear()
        XCTAssertEqual(model.operation, .submitting)

        await cli.resumeSubmit()
        await operation.value
        XCTAssertEqual(model.operation, .succeeded("用量已提交，全部范围已更新。"))
        XCTAssertEqual(model.dashboardOperation, .idle)
    }

    func testClosingDuringFailingOperationSuppressesTerminalBanner() async {
        let cli = SuspendedFailingSubmitCLI()
        let model = makeModel(cli: cli)
        model.panelDidAppear()

        let operation = Task { await model.refresh() }
        await cli.waitForSubmit()
        model.panelDidDisappear()
        XCTAssertEqual(model.operation, .submitting)

        await cli.failSubmit()
        await operation.value
        guard case .failed = model.operation else { return XCTFail("Expected retained failure result") }
        XCTAssertEqual(model.dashboardOperation, .idle)
    }

    private func makeModel(cli: TokscaleCLIService) -> DashboardViewModel {
        DashboardViewModel(
            api: PreviewAPIService(),
            cli: cli,
            preferencesStore: PreviewPreferencesStore(),
            npxLocator: PreviewNpxLocator(),
            cacheStore: PreviewCacheStore()
        )
    }
}

private struct FailingSubmitCLI: TokscaleCLIService {
    func whoAmI(context: TokscaleCommandContext) async throws -> String { "youranreus" }
    func submit(context: TokscaleCommandContext) async throws { throw TestSubmitError.failed }
    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false}"#.utf8))
    }
    func configureAutosubmit(_ configuration: AutosubmitConfiguration, context: TokscaleCommandContext) async throws {}
    func disableAutosubmit(context: TokscaleCommandContext) async throws {}
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {}
}

private actor SuspendedSubmitCLI: TokscaleCLIService {
    private var submitContinuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var submitStarted = false

    func whoAmI(context: TokscaleCommandContext) async throws -> String { "youranreus" }

    func submit(context: TokscaleCommandContext) async throws {
        submitStarted = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        await withCheckedContinuation { submitContinuation = $0 }
    }

    func waitForSubmit() async {
        if submitStarted { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func resumeSubmit() {
        submitContinuation?.resume()
        submitContinuation = nil
    }

    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false}"#.utf8))
    }
    func configureAutosubmit(_ configuration: AutosubmitConfiguration, context: TokscaleCommandContext) async throws {}
    func disableAutosubmit(context: TokscaleCommandContext) async throws {}
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {}
}

private actor SuspendedFailingSubmitCLI: TokscaleCLIService {
    private var submitContinuation: CheckedContinuation<Void, Error>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var submitStarted = false

    func whoAmI(context: TokscaleCommandContext) async throws -> String { "youranreus" }

    func submit(context: TokscaleCommandContext) async throws {
        submitStarted = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        try await withCheckedThrowingContinuation { submitContinuation = $0 }
    }

    func waitForSubmit() async {
        if submitStarted { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func failSubmit() {
        submitContinuation?.resume(throwing: TestSubmitError.failed)
        submitContinuation = nil
    }

    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        try JSONDecoder().decode(AutosubmitStatus.self, from: Data(#"{"enabled":false}"#.utf8))
    }
    func configureAutosubmit(_ configuration: AutosubmitConfiguration, context: TokscaleCommandContext) async throws {}
    func disableAutosubmit(context: TokscaleCommandContext) async throws {}
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {}
}

private enum TestSubmitError: Error { case failed }
