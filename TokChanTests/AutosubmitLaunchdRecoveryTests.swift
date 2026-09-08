import XCTest
@testable import TokChan

final class AutosubmitLaunchdRecoveryTests: XCTestCase {
    private let npxURL = URL(fileURLWithPath: "/test/bin/npx")
    private let context = TokscaleCommandContext(
        npxURL: URL(fileURLWithPath: "/test/bin/npx"),
        version: "4.15.1"
    )
    private let configuration = AutosubmitConfiguration(
        enabled: true,
        intervalMinutes: 120,
        clients: ["codex"],
        filterKind: .week,
        year: "",
        since: "",
        until: ""
    )

    func testConfigureSuccessDoesNotInvokeCompatibilityCleanup() async throws {
        let runner = AutosubmitRecoveryRunner(outputs: [.success])
        let client = makeClient(runner: runner)

        try await client.configureAutosubmit(configuration, context: context)

        let calls = await runner.calls
        XCTAssertEqual(calls, [enableCall])
    }

    func testKnownDefectFromAnotherCommandDoesNotInvokeCompatibilityCleanup() async {
        let runner = AutosubmitRecoveryRunner(outputs: [knownDefect])
        let client = makeClient(runner: runner)

        do {
            try await client.disableAutosubmit(context: context)
            XCTFail("Expected disable failure")
        } catch let TokscaleCLIError.failed(exitCode, _) {
            XCTAssertEqual(exitCode, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let calls = await runner.calls
        XCTAssertEqual(calls, [
            .init(
                executable: npxURL,
                arguments: ["--yes", "tokscale@4.15.1", "autosubmit", "disable"]
            )
        ])
    }

    func testExactDefectRunsFixedCleanupRetriesOnceThenAllowsStatusVerification() async throws {
        let statusJSON = #"{"enabled":true,"intervalMinutes":120,"scheduler":"launchd","clients":["codex"],"week":true,"managedExecutable":"/managed/tokscale","managedExecutableVersion":"4.15.1","managedExecutableStale":false}"#
        let runner = AutosubmitRecoveryRunner(outputs: [
            knownDefect,
            .success,
            .success,
            .success,
            ProcessOutput(exitCode: 0, stdout: statusJSON, stderr: "")
        ])
        let client = makeClient(runner: runner)

        try await client.configureAutosubmit(configuration, context: context)
        let status = try await client.autosubmitStatus(context: context)

        XCTAssertEqual(status.intervalMinutes, 120)
        XCTAssertEqual(status.managedExecutable, "/managed/tokscale")
        XCTAssertEqual(status.managedExecutableVersion, "4.15.1")
        let calls = await runner.calls
        XCTAssertEqual(calls, [
            enableCall,
            .init(
                executable: URL(fileURLWithPath: "/bin/launchctl"),
                arguments: ["bootout", "gui/501/ai.tokscale.autosubmit"]
            ),
            .init(
                executable: npxURL,
                arguments: ["--yes", "tokscale@4.15.1", "autosubmit", "disable"],
                environmentOverrides: ["TOKSCALE_AUTOSUBMIT_SKIP_SCHEDULER": "1"]
            ),
            enableCall,
            .init(
                executable: npxURL,
                arguments: ["--yes", "tokscale@4.15.1", "autosubmit", "status", "--json"]
            )
        ])
        XCTAssertFalse(calls[1].arguments.contains("--wait"))
        XCTAssertEqual(calls[0].environmentOverrides, [:])
        XCTAssertEqual(calls[1].environmentOverrides, [:])
        XCTAssertEqual(calls[2].environmentOverrides, ["TOKSCALE_AUTOSUBMIT_SKIP_SCHEDULER": "1"])
        XCTAssertEqual(calls[3].environmentOverrides, [:])
        XCTAssertEqual(calls[4].environmentOverrides, [:])
    }

    func testNearMatchDefectsFailWithoutCleanupOrRetry() async {
        let nearMatches = [
            knownDefectText.replacingOccurrences(of: "launchd bootout failed", with: "launchd bootstrap failed"),
            knownDefectText.replacingOccurrences(of: "bootout --wait", with: "bootout"),
            knownDefectText.replacingOccurrences(of: "exit status: 64", with: "exit status: 640"),
            knownDefectText.replacingOccurrences(
                of: "Unrecognized target specifier",
                with: "Could not find service"
            )
        ]

        for diagnostic in nearMatches {
            let failure = ProcessOutput(exitCode: 1, stdout: "", stderr: diagnostic)
            let runner = AutosubmitRecoveryRunner(outputs: [failure])
            let client = makeClient(runner: runner)

            do {
                try await client.configureAutosubmit(configuration, context: context)
                XCTFail("Expected the near-match diagnostic to fail")
            } catch let TokscaleCLIError.failed(exitCode, message) {
                XCTAssertEqual(exitCode, 1)
                XCTAssertEqual(message, diagnostic)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }

            let calls = await runner.calls
            XCTAssertEqual(calls, [enableCall])
        }
    }

    func testCleanupFailureIsSurfacedAndStopsBeforeRetry() async {
        let cleanupFailure = ProcessOutput(
            exitCode: 5,
            stdout: "",
            stderr: "Input/output error"
        )
        let runner = AutosubmitRecoveryRunner(outputs: [knownDefect, cleanupFailure])
        let client = makeClient(runner: runner)

        do {
            try await client.configureAutosubmit(configuration, context: context)
            XCTFail("Expected cleanup failure")
        } catch let TokscaleCLIError.autosubmitCompatibilityCleanupFailed(exitCode, message) {
            XCTAssertEqual(exitCode, 5)
            XCTAssertEqual(message, "Input/output error")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let calls = await runner.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.last?.executable.path, "/bin/launchctl")
        XCTAssertEqual(calls.last?.arguments, ["bootout", "gui/501/ai.tokscale.autosubmit"])
    }

    func testCleanupRunnerErrorIsIdentifiedAsCompatibilityFailure() async {
        let runner = AutosubmitRecoveryRunner(outputs: [knownDefect])
        let client = TokscaleCLIClient(
            runner: runner,
            recoveryRunner: FailingAutosubmitRecoveryRunner(),
            effectiveUserID: 501
        )

        do {
            try await client.configureAutosubmit(configuration, context: context)
            XCTFail("Expected cleanup runner failure")
        } catch let TokscaleCLIError.autosubmitCompatibilityCleanupFailed(exitCode, message) {
            XCTAssertNil(exitCode)
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let calls = await runner.calls
        XCTAssertEqual(calls, [enableCall])
    }

    func testStateCleanupFailureIsSurfacedAndStopsBeforeRetry() async {
        let stateCleanupFailure = ProcessOutput(
            exitCode: 9,
            stdout: "",
            stderr: "Unable to clear persisted autosubmit state"
        )
        let runner = AutosubmitRecoveryRunner(outputs: [
            knownDefect,
            .success,
            stateCleanupFailure
        ])
        let client = makeClient(runner: runner)

        do {
            try await client.configureAutosubmit(configuration, context: context)
            XCTFail("Expected state cleanup failure")
        } catch let TokscaleCLIError.autosubmitCompatibilityStateCleanupFailed(exitCode, message) {
            XCTAssertEqual(exitCode, 9)
            XCTAssertEqual(message, "Unable to clear persisted autosubmit state")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let calls = await runner.calls
        XCTAssertEqual(calls, [
            enableCall,
            .init(
                executable: URL(fileURLWithPath: "/bin/launchctl"),
                arguments: ["bootout", "gui/501/ai.tokscale.autosubmit"]
            ),
            .init(
                executable: npxURL,
                arguments: ["--yes", "tokscale@4.15.1", "autosubmit", "disable"],
                environmentOverrides: ["TOKSCALE_AUTOSUBMIT_SKIP_SCHEDULER": "1"]
            )
        ])
    }

    func testRetryFailurePreservesCLIErrorAndDoesNotRecoverAgain() async {
        let runner = AutosubmitRecoveryRunner(outputs: [
            knownDefect,
            .success,
            .success,
            knownDefect
        ])
        let client = makeClient(runner: runner)

        do {
            try await client.configureAutosubmit(configuration, context: context)
            XCTFail("Expected retry failure")
        } catch let TokscaleCLIError.failed(exitCode, message) {
            XCTAssertEqual(exitCode, 1)
            XCTAssertEqual(message, "Unrecognized target specifier")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let calls = await runner.calls
        XCTAssertEqual(calls, [
            enableCall,
            .init(
                executable: URL(fileURLWithPath: "/bin/launchctl"),
                arguments: ["bootout", "gui/501/ai.tokscale.autosubmit"]
            ),
            .init(
                executable: npxURL,
                arguments: ["--yes", "tokscale@4.15.1", "autosubmit", "disable"],
                environmentOverrides: ["TOKSCALE_AUTOSUBMIT_SKIP_SCHEDULER": "1"]
            ),
            enableCall
        ])
    }

    private var knownDefect: ProcessOutput {
        ProcessOutput(
            exitCode: 1,
            stdout: "Error: launchd bootout failed: command `launchctl bootout --wait "
                + "gui/501/ai.tokscale.autosubmit` exited with status exit status: 64; stdout: ; stderr:",
            stderr: "Unrecognized target specifier"
        )
    }

    private var knownDefectText: String {
        knownDefect.stdout + "\n" + knownDefect.stderr
    }

    private var enableCall: AutosubmitRecoveryRunner.Call {
        .init(
            executable: npxURL,
            arguments: [
                "--yes", "tokscale@4.15.1", "autosubmit", "enable",
                "--interval", "120m", "--client", "codex", "--week"
            ]
        )
    }

    private func makeClient(runner: AutosubmitRecoveryRunner) -> TokscaleCLIClient {
        TokscaleCLIClient(runner: runner, effectiveUserID: 501)
    }
}

private actor AutosubmitRecoveryRunner: ProcessRunning {
    struct Call: Equatable {
        let executable: URL
        let arguments: [String]
        let environmentOverrides: [String: String]

        init(
            executable: URL,
            arguments: [String],
            environmentOverrides: [String: String] = [:]
        ) {
            self.executable = executable
            self.arguments = arguments
            self.environmentOverrides = environmentOverrides
        }
    }

    private var outputs: [ProcessOutput]
    private(set) var calls: [Call] = []

    init(outputs: [ProcessOutput]) {
        self.outputs = outputs
    }

    func run(
        executable: URL,
        arguments: [String],
        environmentOverrides: [String: String],
        timeout: TimeInterval
    ) async throws -> ProcessOutput {
        calls.append(Call(
            executable: executable,
            arguments: arguments,
            environmentOverrides: environmentOverrides
        ))
        guard !outputs.isEmpty else { throw ProcessRunnerError.unreadableOutput }
        return outputs.removeFirst()
    }
}

private actor FailingAutosubmitRecoveryRunner: ProcessRunning {
    func run(
        executable: URL,
        arguments: [String],
        environmentOverrides: [String: String],
        timeout: TimeInterval
    ) async throws -> ProcessOutput {
        throw ProcessRunnerError.timedOut
    }
}

private extension ProcessOutput {
    static let success = ProcessOutput(exitCode: 0, stdout: "", stderr: "")
}
