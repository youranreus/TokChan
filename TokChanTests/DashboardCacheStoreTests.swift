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

    func testLegacyUnscopedSnapshotIsRejected() throws {
        let snapshot = DashboardCacheSnapshot(profile: try makeProfile(), autosubmit: nil, savedAt: Date())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        var profile = try XCTUnwrap(json["profile"] as? [String: Any])
        profile.removeValue(forKey: "period")
        json["profile"] = profile
        let legacy = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try JSONDecoder().decode(DashboardCacheSnapshot.self, from: legacy))
    }

    func testMigratesPreviousSingleScopeSnapshot() throws {
        let profile = try makeProfile()
        let snapshot = DashboardCacheSnapshot(profile: profile, autosubmit: nil, savedAt: Date())
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        legacy.removeValue(forKey: "profiles")
        legacy.removeValue(forKey: "selectedPeriod")
        let decoded = try JSONDecoder().decode(DashboardCacheSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.profiles.map(\.data), [profile])
        XCTAssertEqual(decoded.selectedPeriod, .all)
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
