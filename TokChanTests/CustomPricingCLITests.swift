import XCTest
@testable import TokChan

final class CustomPricingCLITests: XCTestCase {
    func testUsesListOverridesPathAndDryRunWithoutRealSubmit() async throws {
        let runner = PricingRunner(outputs: [
            ProcessOutput(exitCode: 0,
                          stdout: #"{"path":"/tmp/tokscale/custom-pricing.json","count":0,"models":[]}"#,
                          stderr: ""),
            ProcessOutput(exitCode: 0,
                          stdout: "Summary\nDry run - not submitting data.",
                          stderr: "")
        ])
        let client = TokscaleCLIClient(runner: runner)
        let context = TokscaleCommandContext(npxURL: URL(fileURLWithPath: "/usr/bin/npx"), version: "4.15.0")

        let url = try await client.customPricingFileURL(context: context)
        let report = try await client.checkCustomPricing(context: context)

        XCTAssertEqual(url.path, "/tmp/tokscale/custom-pricing.json")
        XCTAssertEqual(report.outcome, .noMissingPricing)
        let calls = await runner.calls
        XCTAssertEqual(calls.map(\.arguments), [
            ["--yes", "tokscale@4.15.0", "pricing", "list-overrides", "--json"],
            ["--yes", "tokscale@4.15.0", "submit", "--dry-run"]
        ])
        XCTAssertFalse(calls.contains { $0.arguments.suffix(1) == ["submit"] })
    }

    func testUnsupportedPricingCommandIncludesVersionUpgradeGuidance() async {
        let runner = PricingRunner(outputs: [
            ProcessOutput(exitCode: 2, stdout: "", stderr: "error: unrecognized subcommand 'pricing'")
        ])
        let client = TokscaleCLIClient(runner: runner)
        let context = TokscaleCommandContext(npxURL: URL(fileURLWithPath: "/usr/bin/npx"), version: "4.1.0")

        do {
            _ = try await client.customPricingFileURL(context: context)
            XCTFail("Expected unsupported pricing failure")
        } catch let TokscaleCLIError.unsupportedPricing(version, detail) {
            XCTAssertEqual(version, "4.1.0")
            XCTAssertTrue(detail.contains("unrecognized subcommand"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonzeroDryRunPreservesCLIError() async {
        let runner = PricingRunner(outputs: [
            ProcessOutput(exitCode: 7, stdout: "", stderr: "Not logged in. Run `tokscale login`.")
        ])
        let client = TokscaleCLIClient(runner: runner)
        let context = TokscaleCommandContext(npxURL: URL(fileURLWithPath: "/usr/bin/npx"), version: "latest")

        do {
            _ = try await client.checkCustomPricing(context: context)
            XCTFail("Expected CLI failure")
        } catch let TokscaleCLIError.failed(code, message) {
            XCTAssertEqual(code, 7)
            XCTAssertTrue(message.contains("Not logged in"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor PricingRunner: ProcessRunning {
    struct Call: Equatable {
        let executable: URL
        let arguments: [String]
    }

    private var outputs: [ProcessOutput]
    private(set) var calls: [Call] = []

    init(outputs: [ProcessOutput]) {
        self.outputs = outputs
    }

    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput {
        calls.append(Call(executable: executable, arguments: arguments))
        guard !outputs.isEmpty else { throw ProcessRunnerError.unreadableOutput }
        return outputs.removeFirst()
    }
}
