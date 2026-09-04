import Foundation
import XCTest
@testable import TokChan

final class NpxLocatorTests: XCTestCase {
    func testExecutablePreferredPathTakesPrecedenceOverDiscovery() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferred = root.appendingPathComponent("custom/npx")
        let pathNpx = root.appendingPathComponent("path/npx")
        try makeExecutable(at: preferred)
        try makeExecutable(at: pathNpx)
        let locator = NpxLocator(
            environment: ["PATH": pathNpx.deletingLastPathComponent().path],
            homeDirectory: root,
            systemCandidates: []
        )

        XCTAssertEqual(locator.locate(preferredPath: preferred.path), preferred)
    }

    func testInvalidPreferredPathFallsBackToDiscoveredExecutable() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let pathNpx = root.appendingPathComponent("path/npx")
        try makeExecutable(at: pathNpx)
        let locator = NpxLocator(
            environment: ["PATH": pathNpx.deletingLastPathComponent().path],
            homeDirectory: root,
            systemCandidates: []
        )

        XCTAssertEqual(locator.locate(preferredPath: root.appendingPathComponent("missing/npx").path), pathNpx)
    }

    func testReturnsNilWhenNoCandidateIsExecutable() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let locator = NpxLocator(environment: [:], homeDirectory: root, systemCandidates: [])

        XCTAssertNil(locator.locate(preferredPath: nil))
    }

    func testPathCandidatePrecedesFixedSystemCandidate() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let pathNpx = root.appendingPathComponent("path/bin/npx")
        let systemNpx = root.appendingPathComponent("homebrew/bin/npx")
        try makeExecutable(at: pathNpx)
        try makeExecutable(at: systemNpx)
        let locator = NpxLocator(
            environment: ["PATH": pathNpx.deletingLastPathComponent().path],
            homeDirectory: root,
            systemCandidates: [systemNpx]
        )

        XCTAssertEqual(locator.locate(preferredPath: nil), pathNpx)
    }

    func testFindsNewestNVMVersionNumerically() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let older = root.appendingPathComponent(".nvm/versions/node/v9.9.9/bin/npx")
        let newer = root.appendingPathComponent(".nvm/versions/node/v22.3.0/bin/npx")
        try makeExecutable(at: older)
        try makeExecutable(at: newer)

        let locator = NpxLocator(
            environment: [:],
            homeDirectory: root,
            systemCandidates: []
        )

        XCTAssertEqual(
            locator.locate(preferredPath: nil)?.resolvingSymlinksInPath(),
            newer.resolvingSymlinksInPath()
        )
    }

    func testSystemFallbackPrecedesNVM() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let systemNpx = root.appendingPathComponent("homebrew/bin/npx")
        let nvmNpx = root.appendingPathComponent(".nvm/versions/node/v99.0.0/bin/npx")
        try makeExecutable(at: systemNpx)
        try makeExecutable(at: nvmNpx)

        let locator = NpxLocator(
            environment: [:],
            homeDirectory: root,
            systemCandidates: [systemNpx]
        )

        XCTAssertEqual(locator.locate(preferredPath: nil), systemNpx)
    }

    func testIgnoresRelativePreferredPath() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let npx = root.appendingPathComponent("bin/npx")
        try makeExecutable(at: npx)
        let locator = NpxLocator(
            environment: ["PATH": npx.deletingLastPathComponent().path],
            homeDirectory: root,
            systemCandidates: []
        )

        XCTAssertEqual(locator.locate(preferredPath: "bin/npx"), npx)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChanNpxLocatorTests-\(UUID().uuidString)", isDirectory: true)
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
