import XCTest
@testable import TokChan

final class CursorLoginCLITests: XCTestCase {
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
