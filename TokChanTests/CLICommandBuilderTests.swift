import XCTest
@testable import TokChan

final class CLICommandBuilderTests: XCTestCase {
    func testBuildsVersionedStatusCommand() throws {
        XCTAssertEqual(
            try TokscaleCommandBuilder.arguments(version: "4.15.0", command: .autosubmitStatus),
            ["--yes", "tokscale@4.15.0", "autosubmit", "status", "--json"]
        )
    }

    func testBuildsEveryNonConfigurationCommand() throws {
        let expected: [(TokscaleCommand, [String])] = [
            (.whoami, ["whoami"]),
            (.submit, ["submit"]),
            (.disableAutosubmit, ["autosubmit", "disable"]),
            (.runAutosubmitNow, ["autosubmit", "run", "--force"])
        ]

        for (command, suffix) in expected {
            let arguments = try TokscaleCommandBuilder.arguments(version: "4.15.0", command: command)
            XCTAssertEqual(Array(arguments.dropFirst(2)), suffix)
        }
    }

    func testBuildsCompleteAutosubmitConfiguration() throws {
        let configuration = AutosubmitConfiguration(
            enabled: true,
            intervalMinutes: 120,
            clients: ["codex", "claude"],
            filterKind: .week,
            year: "",
            since: "",
            until: ""
        )

        XCTAssertEqual(
            try TokscaleCommandBuilder.arguments(
                version: "latest",
                command: .configureAutosubmit(configuration)
            ),
            [
                "--yes", "tokscale@latest", "autosubmit", "enable",
                "--interval", "120m", "--client", "codex,claude", "--week"
            ]
        )
    }

    func testRejectsInjectionShapedVersionAndClient() {
        XCTAssertThrowsError(
            try TokscaleCommandBuilder.arguments(version: "latest;rm", command: .submit)
        )

        let configuration = AutosubmitConfiguration(
            enabled: true,
            intervalMinutes: 60,
            clients: ["codex;whoami"],
            filterKind: .all,
            year: "",
            since: "",
            until: ""
        )
        XCTAssertThrowsError(
            try TokscaleCommandBuilder.arguments(
                version: "4.15.0",
                command: .configureAutosubmit(configuration)
            )
        )
    }

    func testBuildsDateRangeWithoutShellInterpolation() throws {
        let configuration = AutosubmitConfiguration(
            enabled: true,
            intervalMinutes: 30,
            clients: [],
            filterKind: .range,
            year: "",
            since: "2026-01-01",
            until: "2026-09-03"
        )
        let arguments = try TokscaleCommandBuilder.arguments(
            version: "4.15.0-beta.1",
            command: .configureAutosubmit(configuration)
        )
        XCTAssertEqual(Array(arguments.suffix(4)), ["--since", "2026-01-01", "--until", "2026-09-03"])
    }

    func testRejectsImpossibleOrReversedDateRange() {
        let impossible = AutosubmitConfiguration(
            enabled: true,
            intervalMinutes: 30,
            clients: [],
            filterKind: .range,
            year: "",
            since: "2026-02-31",
            until: ""
        )
        let reversed = AutosubmitConfiguration(
            enabled: true,
            intervalMinutes: 30,
            clients: [],
            filterKind: .range,
            year: "",
            since: "2026-09-03",
            until: "2026-01-01"
        )

        XCTAssertThrowsError(
            try TokscaleCommandBuilder.arguments(version: "4.15.0", command: .configureAutosubmit(impossible))
        )
        XCTAssertThrowsError(
            try TokscaleCommandBuilder.arguments(version: "4.15.0", command: .configureAutosubmit(reversed))
        )
    }
}
