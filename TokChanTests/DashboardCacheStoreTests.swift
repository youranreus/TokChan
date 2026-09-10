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

    func testRoundTripsSourceIsolatedProfilesAndFetchTimes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChanCacheSources-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json")
        let online = try makeProfile()
        let local = DashboardData(
            period: .all,
            dateRange: online.dateRange,
            breakdown: online.breakdown,
            totalTokens: 7,
            totalCost: 0.07,
            updatedAt: online.updatedAt,
            clients: []
        )
        let onlineDate = Date(timeIntervalSince1970: 100)
        let localDate = Date(timeIntervalSince1970: 200)
        let snapshot = DashboardCacheSnapshot(
            profile: local,
            autosubmit: nil,
            savedAt: localDate,
            profiles: [
                CachedDashboardProfile(data: online, savedAt: onlineDate, source: .online),
                CachedDashboardProfile(data: local, savedAt: localDate, source: .local)
            ],
            fetchedAt: onlineDate,
            fetchedAtBySource: [.online: onlineDate, .local: localDate]
        )
        let store = FileDashboardCacheStore(fileURL: fileURL)

        try store.save(snapshot)

        XCTAssertEqual(store.load(), snapshot)
    }

    func testClearDeletesCurrentAndLegacySnapshots() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChanCacheClear-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = directory.appendingPathComponent("Application Support/snapshot.json")
        let legacy = directory.appendingPathComponent("Caches/snapshot.json")
        try FileManager.default.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("current".utf8).write(to: current)
        try Data("legacy".utf8).write(to: legacy)
        let store = FileDashboardCacheStore(fileURL: current, legacyFileURL: legacy)

        try store.clear()

        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
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
        legacy.removeValue(forKey: "schemaVersion")
        let decoded = try JSONDecoder().decode(DashboardCacheSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.profiles.map(\.data), [profile])
        XCTAssertEqual(decoded.selectedPeriod, .all)
        XCTAssertFalse(decoded.isCompleteBatch)
    }

    func testMigratesSchemaTwoCompleteBatchAsOnlineOnly() throws {
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let profile = try makeProfile()
        let profiles = ProfilePeriod.allCases.map { period in
            CachedDashboardProfile(
                data: DashboardData(
                    period: period,
                    dateRange: profile.dateRange,
                    breakdown: profile.breakdown,
                    username: profile.username,
                    displayName: profile.displayName,
                    avatarURL: profile.avatarURL,
                    rank: profile.rank,
                    totalTokens: profile.totalTokens,
                    totalCost: profile.totalCost,
                    activeDays: profile.activeDays,
                    updatedAt: profile.updatedAt,
                    clients: profile.clients
                ),
                savedAt: fetchedAt
            )
        }
        let snapshot = DashboardCacheSnapshot(
            profile: profiles.first?.data,
            autosubmit: nil,
            savedAt: fetchedAt,
            profiles: profiles,
            schemaVersion: 2,
            username: profile.username,
            fetchedAt: fetchedAt
        )
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        legacy.removeValue(forKey: "fetchedAtBySource")
        legacy["profiles"] = try XCTUnwrap(legacy["profiles"] as? [[String: Any]]).map { entry in
            var migrated = entry
            // Schema 2 had no source contract; even an unexpected stale field must not relabel it as local.
            migrated["source"] = DashboardDataMode.local.rawValue
            return migrated
        }

        let decoded = try JSONDecoder().decode(
            DashboardCacheSnapshot.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )

        XCTAssertTrue(decoded.profiles.allSatisfy { $0.source == .online })
        XCTAssertTrue(decoded.isCompleteBatch(for: .online, account: profile.username))
        XCTAssertFalse(decoded.isCompleteBatch(for: .local))
    }

    func testSourceTimestampDoesNotMakeIncompleteBatchFresh() throws {
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let profile = try makeProfile()
        let snapshot = DashboardCacheSnapshot(
            profile: profile,
            autosubmit: nil,
            savedAt: fetchedAt,
            profiles: [CachedDashboardProfile(data: profile, savedAt: fetchedAt, source: .local)],
            fetchedAtBySource: [.local: fetchedAt]
        )

        XCTAssertFalse(snapshot.isCompleteBatch(for: .local))
    }

    func testCorruptNewSnapshotFallsBackToLegacyCachesFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChanCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let newURL = directory.appendingPathComponent("Application Support/snapshot.json")
        let legacyURL = directory.appendingPathComponent("Caches/snapshot.json")
        try FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: newURL)
        let expected = DashboardCacheSnapshot(profile: try makeProfile(), autosubmit: nil, savedAt: Date())
        try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(expected).write(to: legacyURL)

        let loaded = FileDashboardCacheStore(fileURL: newURL, legacyFileURL: legacyURL).load()

        XCTAssertEqual(loaded, expected)
    }

    func testRejectsUnsupportedFutureSchema() throws {
        let snapshot = DashboardCacheSnapshot(profile: try makeProfile(), autosubmit: nil, savedAt: Date())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        json["schemaVersion"] = DashboardCacheSnapshot.currentSchemaVersion + 1

        XCTAssertThrowsError(try JSONDecoder().decode(
            DashboardCacheSnapshot.self,
            from: JSONSerialization.data(withJSONObject: json)
        ))
    }

    func testAtomicSaveFailurePreservesPreviousSnapshotForNextLaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChanCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("snapshot.json")
        let store = FileDashboardCacheStore(fileURL: fileURL)
        let previous = DashboardCacheSnapshot(
            profile: try makeProfile(),
            autosubmit: nil,
            savedAt: Date(timeIntervalSince1970: 1_788_425_600)
        )
        try store.save(previous)
        let previousBytes = try Data(contentsOf: fileURL)

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let replacement = DashboardCacheSnapshot(
            profile: try makeProfile(),
            autosubmit: try makeAutosubmitStatus(),
            savedAt: Date(timeIntervalSince1970: 1_788_512_000)
        )

        XCTAssertThrowsError(try store.save(replacement))
        XCTAssertEqual(try Data(contentsOf: fileURL), previousBytes)
        XCTAssertEqual(FileDashboardCacheStore(fileURL: fileURL).load(), previous)
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
