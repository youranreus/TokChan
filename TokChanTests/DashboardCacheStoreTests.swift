import Foundation
import XCTest
@testable import TokChan

final class DashboardCacheStoreTests: XCTestCase {
    func testRoundTripsDashboardSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChanCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json")
        let store = FileDashboardCacheStore(fileURL: fileURL)
        let expected = DashboardCacheSnapshot(
            profile: try makeProfile(),
            autosubmit: try makeAutosubmitStatus(),
            savedAt: Date(timeIntervalSince1970: 1_788_425_600)
        )

        try store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testCorruptedCacheIsIgnored() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChanCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL)

        XCTAssertNil(FileDashboardCacheStore(fileURL: fileURL).load())
    }

    private func makeProfile() throws -> DashboardData {
        let response = try JSONDecoder().decode(
            PublicProfileResponse.self,
            from: Data(ProfileModelsTests.profileJSON.utf8)
        )
        return DashboardData(response: response)
    }

    private func makeAutosubmitStatus() throws -> AutosubmitStatus {
        try JSONDecoder().decode(
            AutosubmitStatus.self,
            from: Data(#"{"enabled":true,"intervalMinutes":120,"scheduler":"launchd"}"#.utf8)
        )
    }
}
