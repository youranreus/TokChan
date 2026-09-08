import Foundation
import XCTest
@testable import TokChan

final class ProcessRunnerTests: XCTestCase {
    func testPrependsExecutableDirectoryForEnvShebangResolution() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChanProcessRunnerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let fakeNode = root.appendingPathComponent("fake-node")
        let executable = root.appendingPathComponent("npx")
        try writeExecutable("#!/bin/sh\nprintf 'resolved-node'\n", to: fakeNode)
        try writeExecutable("#!/usr/bin/env fake-node\n", to: executable)

        let output = try await FoundationProcessRunner().run(
            executable: executable,
            arguments: [],
            timeout: 2
        )

        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.stdout, "resolved-node")
        XCTAssertEqual(output.stderr, "")
    }

    func testEnvironmentOverrideIsChildScopedWithoutLosingExecutablePath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChanProcessRunnerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let executable = root.appendingPathComponent("npx")
        try writeExecutable(
            "#!/bin/sh\nprintf '<%s>\\n%s' \"$(/usr/bin/printenv \"$1\")\" \"$PATH\"\n",
            to: executable
        )

        let overrideName = "TOKCHAN_PROCESS_RUNNER_TEST_\(UUID().uuidString)"
        let runner = FoundationProcessRunner()
        let overriddenOutput = try await runner.run(
            executable: executable,
            arguments: [overrideName],
            environmentOverrides: [overrideName: "1"],
            timeout: 2
        )
        let ordinaryOutput = try await runner.run(
            executable: executable,
            arguments: [overrideName],
            timeout: 2
        )

        let overriddenLines = overriddenOutput.stdout.split(separator: "\n", omittingEmptySubsequences: false)
        let ordinaryLines = ordinaryOutput.stdout.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(overriddenOutput.exitCode, 0)
        XCTAssertEqual(ordinaryOutput.exitCode, 0)
        XCTAssertEqual(overriddenLines.first, "<1>")
        XCTAssertEqual(ordinaryLines.first, "<>")
        XCTAssertEqual(overriddenLines.dropFirst().first?.split(separator: ":").first, Substring(root.path))
        XCTAssertEqual(ordinaryLines.dropFirst().first?.split(separator: ":").first, Substring(root.path))
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
