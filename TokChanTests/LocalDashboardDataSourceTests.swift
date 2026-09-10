import XCTest
@testable import TokChan

final class LocalDashboardDataSourceTests: XCTestCase {
    func testAggregatesAllDayTrailingWeekAndTrailingMonthInConfiguredTimezone() async throws {
        let runner = LocalSourceRunner(graphJSON: try fixture("graph"), timezone: "Asia/Shanghai")
        let source = TokscaleLocalDashboardDataSource(runner: runner)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-09T16:00:00Z"))

        let batch = try await source.fetchDashboardBatch(.local(
            context: TokscaleCommandContext(npxURL: URL(fileURLWithPath: "/tmp/npx"), version: "4.15.1"),
            now: now
        ))

        XCTAssertEqual(batch.source, .local)
        XCTAssertNil(batch.account)
        XCTAssertEqual(batch.profiles[.all]?.totalTokens, 111)
        XCTAssertEqual(batch.profiles[.month]?.totalTokens, 110)
        XCTAssertEqual(batch.profiles[.week]?.totalTokens, 100)
        XCTAssertEqual(batch.profiles[.day]?.totalTokens, 70)
        XCTAssertEqual(batch.profiles[.day]?.breakdown, TokenBreakdown(input: 10, output: 20, cacheRead: 30, cacheWrite: 5, reasoning: 5))
        XCTAssertEqual(batch.profiles[.week]?.clients.first?.id, "cursor")
        XCTAssertEqual(batch.profiles[.week]?.clients.first?.tokens, 100)
        XCTAssertEqual(batch.profiles[.week]?.clients.first?.models.first?.tokens, 100)
        XCTAssertEqual(batch.profiles[.month]?.dateRange, ProfileDateRange(start: "2026-08-12", end: "2026-09-10"))

        let commands = await runner.commands
        XCTAssertEqual(Set(commands), Set([
            ["--yes", "tokscale@4.15.1", "config", "get", "timezone"],
            ["--yes", "tokscale@4.15.1", "graph", "--no-spinner"]
        ]))
    }

    func testNoTodayDataUsesConfiguredTodayAndDoesNotReuseLastUsageDate() async throws {
        let source = TokscaleLocalDashboardDataSource(
            runner: LocalSourceRunner(graphJSON: try fixture("graph"), timezone: "Asia/Shanghai")
        )
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-10T16:00:00Z"))

        let batch = try await source.fetchDashboardBatch(.local(
            context: TokscaleCommandContext(npxURL: URL(fileURLWithPath: "/tmp/npx"), version: "4.15.1"),
            now: now
        ))

        XCTAssertEqual(batch.profiles[.day]?.totalTokens, 0)
        XCTAssertEqual(batch.profiles[.day]?.dateRange, ProfileDateRange(start: "2026-09-11", end: "2026-09-11"))
        XCTAssertEqual(batch.profiles[.week]?.totalTokens, 70)
        XCTAssertEqual(batch.profiles[.month]?.totalTokens, 100)
    }

    func testEmptyGraphIsAValidZeroUsageBatch() async throws {
        let source = TokscaleLocalDashboardDataSource(
            runner: LocalSourceRunner(graphJSON: try fixture("empty"), timezone: "UTC")
        )
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-10T08:00:00Z"))

        let batch = try await source.fetchDashboardBatch(.local(
            context: TokscaleCommandContext(npxURL: URL(fileURLWithPath: "/tmp/npx"), version: "latest"),
            now: now
        ))

        XCTAssertEqual(Set(batch.profiles.keys), Set(ProfilePeriod.allCases))
        XCTAssertTrue(batch.profiles.values.allSatisfy { profile in
            profile.totalTokens == 0 && profile.totalCost == 0 && profile.clients.isEmpty
        })
        XCTAssertEqual(batch.profiles[.all]?.dateRange, ProfileDateRange(start: nil, end: nil))
        XCTAssertEqual(batch.profiles[.day]?.dateRange, ProfileDateRange(start: "2026-09-10", end: "2026-09-10"))
    }

    func testMissingPricingDiagnosticsProduceBoundedWarningWithoutChangingUsage() async throws {
        let runner = LocalSourceRunner(
            graphJSON: try fixture("graph"),
            timezone: "UTC",
            graphStderr: try fixture("missing-pricing", extension: "txt")
        )
        let source = TokscaleLocalDashboardDataSource(runner: runner)

        let batch = try await source.fetchDashboardBatch(.local(
            context: TokscaleCommandContext(npxURL: URL(fileURLWithPath: "/tmp/npx"), version: "4.15.1"),
            now: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-10T08:00:00Z"))
        ))

        XCTAssertEqual(batch.profiles[.all]?.totalTokens, 111)
        XCTAssertEqual(batch.warnings, ["Tokscale 报告部分模型缺少价格，本次成本可能不完整。"])
        XCTAssertFalse(batch.warnings.joined().contains("fixture-model"))
    }

    func testInvalidTimezoneFailsInsteadOfGuessingHostTimezone() async throws {
        let runner = LocalSourceRunner(graphJSON: try fixture("graph"), timezone: "Not/A-Timezone")
        let source = TokscaleLocalDashboardDataSource(runner: runner)

        do {
            _ = try await source.fetchDashboardBatch(.local(
                context: TokscaleCommandContext(npxURL: URL(fileURLWithPath: "/tmp/npx"), version: "latest"),
                now: Date()
            ))
            XCTFail("Expected invalid timezone")
        } catch let error as DashboardSourceError {
            guard case .invalidTimezone = error else { return XCTFail("Unexpected error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedGraphIsNotReportedAsZeroUsage() async throws {
        let source = TokscaleLocalDashboardDataSource(
            runner: LocalSourceRunner(graphJSON: try fixture("incompatible"), timezone: "UTC")
        )
        do {
            _ = try await source.fetchDashboardBatch(.local(
                context: TokscaleCommandContext(npxURL: URL(fileURLWithPath: "/tmp/npx"), version: "latest"),
                now: Date()
            ))
            XCTFail("Expected invalid graph")
        } catch let error as DashboardSourceError {
            guard case let .incompatibleCLI(version, detail) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(version, "latest")
            XCTAssertTrue(detail.contains("graph JSON"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInvalidContributionValuesAreNotPublishedAsUsage() async {
        let json = #"{"summary":{"totalTokens":-1,"totalCost":0},"contributions":[{"date":"2026-09-10","totals":{"tokens":-1,"cost":0},"tokenBreakdown":{"input":-1},"clients":[]}]}"#
        let source = TokscaleLocalDashboardDataSource(
            runner: LocalSourceRunner(graphJSON: json, timezone: "UTC")
        )

        do {
            _ = try await source.fetchDashboardBatch(.local(
                context: TokscaleCommandContext(npxURL: URL(fileURLWithPath: "/tmp/npx"), version: "latest"),
                now: Date()
            ))
            XCTFail("Expected invalid graph")
        } catch let error as DashboardSourceError {
            guard case .invalidGraph = error else { return XCTFail("Unexpected error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSummaryMismatchIsNotPublishedAsZeroOrPartialUsage() async {
        let json = #"{"summary":{"totalTokens":100,"totalCost":1},"contributions":[]}"#
        let source = TokscaleLocalDashboardDataSource(
            runner: LocalSourceRunner(graphJSON: json, timezone: "UTC")
        )

        do {
            _ = try await source.fetchDashboardBatch(.local(
                context: TokscaleCommandContext(npxURL: URL(fileURLWithPath: "/tmp/npx"), version: "latest"),
                now: Date()
            ))
            XCTFail("Expected invalid graph")
        } catch let error as DashboardSourceError {
            guard case .invalidGraph = error else { return XCTFail("Unexpected error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testContributionTokenMismatchIsRejected() async {
        let json = #"{"summary":{"totalTokens":10,"totalCost":0},"contributions":[{"date":"2026-09-10","totals":{"tokens":10,"cost":0},"tokenBreakdown":{"input":9},"clients":[{"client":"codex","modelId":"model","tokens":{"input":10},"cost":0}]}]}"#
        let source = TokscaleLocalDashboardDataSource(
            runner: LocalSourceRunner(graphJSON: json, timezone: "UTC")
        )

        do {
            _ = try await source.fetchDashboardBatch(.local(
                context: TokscaleCommandContext(npxURL: URL(fileURLWithPath: "/tmp/npx"), version: "latest"),
                now: Date()
            ))
            XCTFail("Expected invalid graph")
        } catch let error as DashboardSourceError {
            guard case .invalidGraph = error else { return XCTFail("Unexpected error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func fixture(_ name: String, extension fileExtension: String = "json") throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: fileExtension))
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private actor LocalSourceRunner: ProcessRunning {
    let graphJSON: String
    let timezone: String
    let graphStderr: String
    private(set) var commands: [[String]] = []

    init(graphJSON: String, timezone: String, graphStderr: String = "diagnostics stay separate") {
        self.graphJSON = graphJSON
        self.timezone = timezone
        self.graphStderr = graphStderr
    }

    func run(
        executable: URL,
        arguments: [String],
        environmentOverrides: [String: String],
        timeout: TimeInterval
    ) async throws -> ProcessOutput {
        commands.append(arguments)
        if arguments.suffix(3) == ["config", "get", "timezone"] {
            return ProcessOutput(exitCode: 0, stdout: timezone + "\n", stderr: "")
        }
        return ProcessOutput(exitCode: 0, stdout: graphJSON, stderr: graphStderr)
    }
}
