import Foundation
import XCTest
@testable import TokChan

final class NpxLocatorTests: XCTestCase {
    func testFindsNewestNVMVersionNumerically() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChanNpxLocatorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let older = root.appendingPathComponent(".nvm/versions/node/v9.9.9/bin/npx")
        let newer = root.appendingPathComponent(".nvm/versions/node/v22.3.0/bin/npx")
        try makeExecutable(at: older)
        try makeExecutable(at: newer)

        let locator = NpxLocator(environment: [:], homeDirectory: root)

        XCTAssertEqual(
            locator.locate(preferredPath: nil)?.resolvingSymlinksInPath(),
            newer.resolvingSymlinksInPath()
        )
    }

    func testIgnoresRelativePreferredPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChanNpxLocatorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let npx = root.appendingPathComponent("bin/npx")
        try makeExecutable(at: npx)
        let locator = NpxLocator(
            environment: ["PATH": npx.deletingLastPathComponent().path],
            homeDirectory: root
        )

        XCTAssertEqual(locator.locate(preferredPath: "bin/npx"), npx)
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
