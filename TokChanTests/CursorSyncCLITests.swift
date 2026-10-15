import XCTest
@testable import TokChan

final class CursorSyncCLITests: XCTestCase {
    private let context = TokscaleCommandContext(
        npxURL: URL(fileURLWithPath: "/fixture/node/bin/npx"), version: "4.15.0"
    )

    func testExactCommandAndSuccessfulResultsIncludingZeroRowsAndExtraFields() async throws {
        for json in [
            #"{"synced":true,"rows":7046,"error":null}"#,
            #"{"synced":true,"rows":0}"#,
            #"{"synced":true,"rows":3,"error":null,"accounts":2}"#
        ] {
            let runner = SyncRunner(result: .success(.init(exitCode: 0, stdout: json, stderr: "")))
            try await TokscaleCLIClient(runner: runner).syncCursor(context: context)
            let calls = await runner.calls
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls.first?.executable, context.npxURL)
            XCTAssertEqual(calls.first?.arguments, ["--yes", "tokscale@4.15.0", "cursor", "sync", "--json"])
            XCTAssertEqual(calls.first?.timeout, 300)
            XCTAssertEqual(calls.first?.environment, [:])
        }
        XCTAssertEqual(try TokscaleCommandBuilder.arguments(version: "latest", command: .cursorSync),
                       ["--yes", "tokscale@latest", "cursor", "sync", "--json"])
    }

    func testUnsuccessfulAndPartialAccountResultsFailClosedWithoutExposingResponse() async {
        for json in [
            #"{"synced":false,"rows":0,"error":null}"#,
            #"{"synced":true,"rows":5,"error":"secret account diagnostic"}"#,
            #"{"synced":true,"rows":5,"error":""}"#
        ] {
            do {
                try await client(stdout: json).syncCursor(context: context)
                XCTFail("Expected sync failure")
            } catch TokscaleCLIError.cursorSyncFailed {
                XCTAssertFalse(errorText(TokscaleCLIError.cursorSyncFailed).contains("secret"))
            } catch { XCTFail("Unexpected error: \(error)") }
        }
    }

    func testInvalidJSONMissingFieldsAndWrongTypesFailClosed() async {
        for json in ["", "not json", "[]", "null", "{}",
                     #"{"synced":true}"#, #"{"rows":0}"#,
                     #"{"synced":null,"rows":0}"#, #"{"synced":1,"rows":0}"#,
                     #"{"synced":"true","rows":0}"#, #"{"synced":true,"rows":"0"}"#,
                     #"{"synced":true,"rows":-1}"#, #"{"synced":true,"rows":1.5}"#,
                     #"{"synced":true,"rows":true}"#, #"{"synced":true,"rows":null}"#,
                     #"{"synced":true,"rows":0,"error":false}"#,
                     #"{"synced":true,"rows":0,"error":{}}"#] {
            do {
                try await client(stdout: json).syncCursor(context: context)
                XCTFail("Expected invalid result for \(json)")
            } catch TokscaleCLIError.invalidCursorSyncResult {
                // Never include the raw response in the error.
            } catch { XCTFail("Unexpected error for \(json): \(error)") }
        }
    }

    func testNonzeroExitCannotBeOverriddenBySuccessfulJSON() async {
        let runner = SyncRunner(result: .success(.init(
            exitCode: 7, stdout: #"{"synced":true,"rows":0}"#, stderr: "unsupported command"
        )))
        do {
            try await TokscaleCLIClient(runner: runner).syncCursor(context: context)
            XCTFail("Expected process failure")
        } catch let TokscaleCLIError.failed(code, detail) {
            XCTAssertEqual(code, 7)
            XCTAssertEqual(detail, "unsupported command")
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testTimeoutAndCancellationArePreserved() async {
        for failure: Error in [ProcessRunnerError.timedOut, CancellationError()] {
            let runner = SyncRunner(result: .failure(failure))
            do {
                try await TokscaleCLIClient(runner: runner).syncCursor(context: context)
                XCTFail("Expected thrown process error")
            } catch {
                XCTAssertEqual(String(reflecting: type(of: error)), String(reflecting: type(of: failure)))
            }
            let count = await runner.calls.count
            XCTAssertEqual(count, 1)
        }
    }

    func testInvalidVersionStartsNoProcess() async {
        let runner = SyncRunner(result: .success(.init(exitCode: 0, stdout: "", stderr: "")))
        do {
            try await TokscaleCLIClient(runner: runner).syncCursor(context: .init(
                npxURL: context.npxURL, version: "latest;rm"
            ))
            XCTFail("Expected invalid version")
        } catch TokscaleCLIError.invalidVersion {
            let count = await runner.calls.count
            XCTAssertEqual(count, 0)
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    private func client(stdout: String) -> TokscaleCLIClient {
        TokscaleCLIClient(runner: SyncRunner(result: .success(.init(exitCode: 0, stdout: stdout, stderr: ""))))
    }

    private func errorText(_ error: LocalizedError) -> String { error.errorDescription ?? "" }
}

private actor SyncRunner: ProcessRunning {
    struct Call {
        let executable: URL
        let arguments: [String]
        let environment: [String: String]
        let timeout: TimeInterval
    }
    let result: Result<ProcessOutput, Error>
    private(set) var calls: [Call] = []
    init(result: Result<ProcessOutput, Error>) { self.result = result }
    func run(executable: URL, arguments: [String], environmentOverrides: [String: String],
             timeout: TimeInterval) async throws -> ProcessOutput {
        calls.append(.init(executable: executable, arguments: arguments,
                           environment: environmentOverrides, timeout: timeout))
        return try result.get()
    }
}
