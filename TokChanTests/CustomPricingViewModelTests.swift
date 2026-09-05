import XCTest
@testable import TokChan

@MainActor
final class CustomPricingViewModelTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChan-CustomPricingVM-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("custom-pricing.json")
        try Data(#"{"models":{"gpt-new":{"input_cost_per_million_tokens":1,"extension":"keep"}}}"#.utf8)
            .write(to: fileURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testFixingExistingCoverageEditsInsteadOfAddingAndMarksReportStale() async throws {
        let cli = PricingCLIStub(
            url: fileURL,
            report: PricingDiagnosticReport(
                outcome: .missingPricing,
                items: [MissingPricingItem(providerModel: "openai/GPT-NEW", provider: "openai",
                                           modelID: "GPT-NEW", messageCount: 2, tokenCount: 100,
                                           reason: "missing")],
                warnings: [], details: "fixture", checkedAt: Date()
            )
        )
        let model = makeModel(cli: cli)
        await model.load()
        await model.checkMissingPricing()

        let item = try XCTUnwrap(model.report?.items.first)
        model.beginFixing(item)
        XCTAssertEqual(model.editorMode, .edit(originalModelID: "gpt-new"))
        model.draft.outputPrice = "2"
        model.saveDraft()

        XCTAssertEqual(model.entries.count, 1)
        XCTAssertEqual(model.entries.first?.outputPrice, 2)
        XCTAssertTrue(model.isReportStale)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        let entry = try XCTUnwrap((root["models"] as? [String: Any])?["gpt-new"] as? [String: Any])
        XCTAssertEqual(entry["extension"] as? String, "keep")
    }

    func testFixingSyntheticModelEditsNormalizedCoverageWithoutDuplicate() async throws {
        try Data(#"{"models":{"glm-4.7":{"input_cost_per_million_tokens":1}}}"#.utf8)
            .write(to: fileURL)
        let item = MissingPricingItem(
            providerModel: "synthetic/hf:zai-org/GLM-4.7",
            provider: "synthetic",
            modelID: "hf:zai-org/GLM-4.7",
            messageCount: 1,
            tokenCount: 10,
            reason: "missing"
        )
        let model = makeModel(cli: PricingCLIStub(url: fileURL, report: cleanReport))
        await model.load()

        XCTAssertTrue(model.hasMatchingCoverage(for: item))
        model.beginFixing(item)
        XCTAssertEqual(model.editorMode, .edit(originalModelID: "glm-4.7"))
        model.draft.outputPrice = "2"
        model.saveDraft()

        XCTAssertEqual(model.entries.count, 1)
        XCTAssertEqual(model.entries.first?.modelID, "glm-4.7")
        XCTAssertEqual(model.entries.first?.outputPrice, 2)
    }

    func testCancelEditorDoesNotWriteFile() async {
        let cli = PricingCLIStub(url: fileURL, report: cleanReport)
        let model = makeModel(cli: cli)
        await model.load()
        let before = try? Data(contentsOf: fileURL)

        if let entry = model.entries.first { model.beginEdit(entry) }
        model.draft.inputPrice = "999"
        model.cancelEditing()

        XCTAssertEqual(try? Data(contentsOf: fileURL), before)
    }

    func testConfigurationChangeBlocksWritesAndChecksUntilReload() async throws {
        let cli = PricingCLIStub(url: fileURL, report: cleanReport)
        let preferences = PricingPreferences(
            value: UserPreferences(username: "", tokscaleVersion: "4.15.0", npxPath: "/saved/npx")
        )
        let model = CustomPricingViewModel(
            cli: cli,
            store: CustomPricingFileStore(),
            preferencesStore: preferences,
            npxLocator: PricingNpxLocator()
        )
        await model.load()
        let before = try Data(contentsOf: fileURL)
        preferences.value.tokscaleVersion = "4.15.1"

        model.beginAdd()
        model.draft.modelID = "must-not-save"
        model.draft.inputPrice = "1"
        model.saveDraft()
        await model.checkMissingPricing()

        XCTAssertEqual(try Data(contentsOf: fileURL), before)
        XCTAssertNil(model.report)
        guard case let .failed(message) = model.operation else {
            return XCTFail("Expected stale configuration failure")
        }
        XCTAssertTrue(message.contains("重新载入"))
        let contexts = await cli.contexts
        XCTAssertEqual(contexts.count, 1, "A stale snapshot must not launch dry-run")
    }

    func testLateCheckIsMarkedStaleWhenPersistedContextChanges() async throws {
        let cli = SuspendedPricingCLI(url: fileURL, report: cleanReport)
        let preferences = PricingPreferences(
            value: UserPreferences(username: "", tokscaleVersion: "4.15.0", npxPath: "/saved/npx")
        )
        let model = CustomPricingViewModel(
            cli: cli,
            store: CustomPricingFileStore(),
            preferencesStore: preferences,
            npxLocator: PricingNpxLocator()
        )
        await model.load()

        let task = Task { await model.checkMissingPricing() }
        await cli.waitUntilCheckStarts()
        preferences.value.tokscaleVersion = "4.15.1"
        await cli.resumeCheck()
        await task.value

        XCTAssertEqual(model.report?.outcome, .noMissingPricing)
        XCTAssertTrue(model.isReportStale)
    }

    func testCheckUsesPersistedVersionAndNpxContext() async {
        let cli = PricingCLIStub(url: fileURL, report: cleanReport)
        let preferences = PricingPreferences(
            value: UserPreferences(username: "", tokscaleVersion: "4.15.0", npxPath: "/saved/npx")
        )
        let model = CustomPricingViewModel(
            cli: cli,
            store: CustomPricingFileStore(),
            preferencesStore: preferences,
            npxLocator: PricingNpxLocator()
        )

        await model.load()
        await model.checkMissingPricing()

        let contexts = await cli.contexts
        XCTAssertEqual(contexts.count, 2)
        XCTAssertTrue(contexts.allSatisfy { $0.version == "4.15.0" && $0.npxURL.path == "/saved/npx" })
    }

    private var cleanReport: PricingDiagnosticReport {
        PricingDiagnosticReport(outcome: .noMissingPricing, items: [], warnings: [],
                                details: "Dry run", checkedAt: Date())
    }

    private func makeModel(cli: PricingCLIStub) -> CustomPricingViewModel {
        CustomPricingViewModel(
            cli: cli,
            store: CustomPricingFileStore(),
            preferencesStore: PricingPreferences(
                value: UserPreferences(username: "", tokscaleVersion: "4.15.0", npxPath: "/saved/npx")
            ),
            npxLocator: PricingNpxLocator()
        )
    }
}

private actor PricingCLIStub: CustomPricingCLIService {
    let url: URL
    let report: PricingDiagnosticReport
    private(set) var contexts: [TokscaleCommandContext] = []

    init(url: URL, report: PricingDiagnosticReport) {
        self.url = url
        self.report = report
    }

    func customPricingFileURL(context: TokscaleCommandContext) async throws -> URL {
        contexts.append(context)
        return url
    }

    func checkCustomPricing(context: TokscaleCommandContext) async throws -> PricingDiagnosticReport {
        contexts.append(context)
        return report
    }
}

private actor SuspendedPricingCLI: CustomPricingCLIService {
    let url: URL
    let report: PricingDiagnosticReport
    private var checkContinuation: CheckedContinuation<PricingDiagnosticReport, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var checkStarted = false

    init(url: URL, report: PricingDiagnosticReport) {
        self.url = url
        self.report = report
    }

    func customPricingFileURL(context: TokscaleCommandContext) async throws -> URL { url }

    func checkCustomPricing(context: TokscaleCommandContext) async throws -> PricingDiagnosticReport {
        checkStarted = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        return await withCheckedContinuation { checkContinuation = $0 }
    }

    func waitUntilCheckStarts() async {
        if checkStarted { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func resumeCheck() {
        checkContinuation?.resume(returning: report)
        checkContinuation = nil
    }
}

private final class PricingPreferences: PreferencesStoring {
    var value: UserPreferences
    init(value: UserPreferences) { self.value = value }
    func load() -> UserPreferences { value }
    func save(_ preferences: UserPreferences) { value = preferences }
}

private struct PricingNpxLocator: NpxLocating {
    func locate(preferredPath: String?) -> URL? {
        URL(fileURLWithPath: preferredPath ?? "/automatic/npx")
    }
}
