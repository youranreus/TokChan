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

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
