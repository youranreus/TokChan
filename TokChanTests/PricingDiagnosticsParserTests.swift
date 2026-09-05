import XCTest
@testable import TokChan

final class PricingDiagnosticsParserTests: XCTestCase {
    private let parser = PricingDiagnosticsParser()
    private let date = Date(timeIntervalSince1970: 1_788_425_600)

    func testParses415ExcludedDiagnosticsBeforeZeroSummary() throws {
        let output = ProcessOutput(
            exitCode: 0,
            stdout: """
            Tokscale - Submit Usage Data
              Warning: excluded 12 unpriced anthropic/claude-new message(s) (1,234,567 tokens): Missing pricing for model 'claude-new'.
              Data to submit:
              No usage data found to submit.
            """,
            stderr: "\u{001B}[33m[tokscale] Warning: Failed to cache models.dev pricing\u{001B}[0m"
        )

        let report = parser.parse(output, checkedAt: date)

        XCTAssertEqual(report.outcome, .missingPricing)
        let item = try XCTUnwrap(report.items.first)
        XCTAssertEqual(item.provider, "anthropic")
        XCTAssertEqual(item.modelID, "claude-new")
        XCTAssertEqual(item.messageCount, 12)
        XCTAssertEqual(item.tokenCount, 1_234_567)
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertFalse(report.details.contains("\u{001B}"))
    }

    func testParsesCurrentZeroCostDiagnostic() throws {
        let output = ProcessOutput(
            exitCode: 0,
            stdout: "Warning: submitting 3 unpriced openai/gpt-unknown message(s) (42,000 tokens) at $0.00: Missing pricing for model 'gpt-unknown'. Affected days are marked cost-incomplete so they cannot lower previously recorded spend.\nDry run - not submitting data.",
            stderr: ""
        )

        let report = parser.parse(output, checkedAt: date)

        XCTAssertEqual(report.outcome, .missingPricing)
        XCTAssertEqual(report.items.first?.modelID, "gpt-unknown")
        XCTAssertTrue(report.items.first?.reason.contains("$0") == true)
    }

    func testParsesCurrentCappedRowsAndModelIDsContainingSlashes() throws {
        let output = ProcessOutput(
            exitCode: 0,
            stdout: """
            Warning: submitting 9 unpriced gateway/org/model-v2 message(s) (1,001 tokens) at $0.00: Missing pricing.
              ... and 2 more at $0.00:
                other/team/model-a, third/model-b
              Unpriced total: 12 message(s) (2,000 tokens) at $0.00 across 3 provider/model(s).
            Dry run - not submitting data.
            """,
            stderr: ""
        )

        let report = parser.parse(output, checkedAt: date)

        XCTAssertEqual(report.outcome, .missingPricing)
        XCTAssertEqual(report.items.map(\.providerModel), [
            "gateway/org/model-v2", "other/team/model-a", "third/model-b"
        ])
        XCTAssertEqual(report.items.first?.provider, "gateway")
        XCTAssertEqual(report.items.first?.modelID, "org/model-v2")
        XCTAssertNil(report.items[1].messageCount)
    }

    func testDistinguishesNoDataCleanAndUnknownOutput() {
        XCTAssertEqual(
            parser.parse(ProcessOutput(exitCode: 0, stdout: "No usage data found to submit.", stderr: ""), checkedAt: date).outcome,
            .noData
        )
        XCTAssertEqual(
            parser.parse(ProcessOutput(exitCode: 0, stdout: "Summary\nDry run - not submitting data.", stderr: ""), checkedAt: date).outcome,
            .noMissingPricing
        )
        XCTAssertEqual(
            parser.parse(ProcessOutput(exitCode: 0, stdout: "New report format", stderr: ""), checkedAt: date).outcome,
            .unknownFormat
        )
    }

    func testDataSourceWarningProducesPartialResultInsteadOfPass() {
        let direct = parser.parse(
            ProcessOutput(exitCode: 0,
                          stdout: "Dry run - not submitting data.",
                          stderr: "Warning: Cursor sync failed"),
            checkedAt: date
        )
        let section = parser.parse(
            ProcessOutput(exitCode: 0,
                          stdout: "Warnings:\n• Cursor source unavailable\nDry run - not submitting data.",
                          stderr: ""),
            checkedAt: date
        )
        XCTAssertEqual(direct.outcome, .partialData)
        XCTAssertEqual(section.outcome, .partialData)
    }

    func testEmptyWarningsHeadingDoesNotTurnCleanRunIntoPartial() {
        let report = parser.parse(
            ProcessOutput(exitCode: 0,
                          stdout: "Summary:\nWarnings:\nDry run - not submitting data.",
                          stderr: ""),
            checkedAt: date
        )
        XCTAssertEqual(report.outcome, .noMissingPricing)
        XCTAssertTrue(report.warnings.isEmpty)
    }

    func testUnrecognizedPricingFailureCannotBecomeSuccess() {
        let report = parser.parse(
            ProcessOutput(exitCode: 0,
                          stdout: "pricing data is unavailable for submission\nDry run - not submitting data.",
                          stderr: ""),
            checkedAt: date
        )
        XCTAssertEqual(report.outcome, .unknownFormat)
    }
}
