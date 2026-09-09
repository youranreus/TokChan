import XCTest
@testable import TokChan

final class CursorLoginCLITests: XCTestCase {
    func testCursorStatusRunsExactlyOneReadOnlyDiscreteCommand() async throws {
        let runner = CursorLoginRunner(output: ProcessOutput(
            exitCode: 0,
            stdout: "Cursor account\nSession: Valid\n",
            stderr: ""
        ))
        let client = TokscaleCLIClient(runner: runner, timeout: 12)
        let context = TokscaleCommandContext(
            npxURL: URL(fileURLWithPath: "/test/node/bin/npx"),
            version: "4.15.0"
        )

        let status = try await client.cursorStatus(context: context)
        XCTAssertEqual(status, .valid)
        let calls = await runner.calls
        XCTAssertEqual(calls, [
            .init(
                executable: URL(fileURLWithPath: "/test/node/bin/npx"),
                arguments: ["--yes", "tokscale@4.15.0", "cursor", "status"],
                environmentOverrides: [:],
                timeout: 12
            )
        ])
        XCTAssertNotEqual(calls.first?.executable.path, "/bin/sh")
    }

    func testCursorStatusParserRecognizesOnlyStableMarkersAndStripsANSI() {
        let parser = CursorSessionStatusParser()
        let fixtures: [(String, String, CursorSessionStatus)] = [
            ("Session: Valid\n", "", .valid),
            ("\u{001B}[32mSession: Valid\u{001B}[0m\n", "", .valid),
            ("⚠ No saved Cursor accounts.\nRun cursor login", "", .unavailable),
            ("", "Session: Session token expired or invalid\n", .unavailable),
            ("Session: network request failed", "", .indeterminate),
            ("Session: HTTP 503", "", .indeterminate),
            ("Session: unable to parse response", "", .indeterminate),
            ("", "", .indeterminate),
            ("Session: Valid account for someone", "", .indeterminate),
            ("unknown output", "", .indeterminate)
        ]

        for (stdout, stderr, expected) in fixtures {
            XCTAssertEqual(
                parser.parse(ProcessOutput(exitCode: 0, stdout: stdout, stderr: stderr)),
                expected,
                "Unexpected classification for stdout=\(stdout), stderr=\(stderr)"
            )
        }
    }

    func testCursorStatusRejectsInvalidVersionBeforeLaunching() async {
        let runner = CursorLoginRunner(output: ProcessOutput(exitCode: 0, stdout: "Session: Valid", stderr: ""))
        let client = TokscaleCLIClient(runner: runner)

        do {
            _ = try await client.cursorStatus(context: TokscaleCommandContext(
                npxURL: URL(fileURLWithPath: "/usr/bin/npx"),
                version: "latest;rm"
            ))
            XCTFail("Expected invalid version")
        } catch TokscaleCLIError.invalidVersion {
            let calls = await runner.calls
            XCTAssertTrue(calls.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCursorStatusPreservesNonzeroExitAndTimeoutFailures() async {
        let context = TokscaleCommandContext(
            npxURL: URL(fileURLWithPath: "/usr/bin/npx"),
            version: "latest"
        )
        let failingClient = TokscaleCLIClient(runner: CursorLoginRunner(
            output: ProcessOutput(exitCode: 7, stdout: "", stderr: "unsupported cursor status")
        ))
        do {
            _ = try await failingClient.cursorStatus(context: context)
            XCTFail("Expected nonzero exit")
        } catch let TokscaleCLIError.failed(exitCode, message) {
            XCTAssertEqual(exitCode, 7)
            XCTAssertEqual(message, "unsupported cursor status")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let timeoutClient = TokscaleCLIClient(runner: ThrowingCursorStatusRunner())
        do {
            _ = try await timeoutClient.cursorStatus(context: context)
            XCTFail("Expected timeout")
        } catch ProcessRunnerError.timedOut {
            // Expected: the process boundary owns timeout and cancellation.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoginRunsExactlyOneDiscreteCursorCommandThroughResolvedExecutable() async throws {
        let runner = CursorLoginRunner(output: ProcessOutput(exitCode: 0, stdout: "Logged in", stderr: ""))
        let client = TokscaleCLIClient(runner: runner, timeout: 12)
        let context = TokscaleCommandContext(
            npxURL: URL(fileURLWithPath: "/test/node/bin/npx"),
            version: "4.15.0"
        )

        try await client.loginCursor(context: context)

        let calls = await runner.calls
        XCTAssertEqual(calls, [
            .init(
                executable: URL(fileURLWithPath: "/test/node/bin/npx"),
                arguments: ["--yes", "tokscale@4.15.0", "cursor", "login"],
                environmentOverrides: [:],
                timeout: 12
            )
        ])
        XCTAssertNotEqual(calls.first?.executable.path, "/bin/sh")
    }

    func testLoginReusesBoundedNonzeroExitError() async {
        let detail = String(repeating: "x", count: 4_100)
        let runner = CursorLoginRunner(
            output: ProcessOutput(exitCode: 9, stdout: "", stderr: detail)
        )
        let client = TokscaleCLIClient(runner: runner)

        do {
            try await client.loginCursor(context: TokscaleCommandContext(
                npxURL: URL(fileURLWithPath: "/usr/bin/npx"),
                version: "latest"
            ))
            XCTFail("Expected login failure")
        } catch let TokscaleCLIError.failed(exitCode, message) {
            XCTAssertEqual(exitCode, 9)
            XCTAssertEqual(message.count, 4_000)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct ThrowingCursorStatusRunner: ProcessRunning {
    func run(
        executable: URL,
        arguments: [String],
        environmentOverrides: [String: String],
        timeout: TimeInterval
    ) async throws -> ProcessOutput {
        throw ProcessRunnerError.timedOut
    }
}

private actor CursorLoginRunner: ProcessRunning {
    struct Call: Equatable {
        let executable: URL
        let arguments: [String]
        let environmentOverrides: [String: String]
        let timeout: TimeInterval
    }

    private let output: ProcessOutput
    private(set) var calls: [Call] = []

    init(output: ProcessOutput) {
        self.output = output
    }

    func run(
        executable: URL,
        arguments: [String],
        environmentOverrides: [String: String],
        timeout: TimeInterval
    ) async throws -> ProcessOutput {
        calls.append(.init(
            executable: executable,
            arguments: arguments,
            environmentOverrides: environmentOverrides,
            timeout: timeout
        ))
        return output
    }
}
