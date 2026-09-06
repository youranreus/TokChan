import Foundation

struct CachedDashboardProfile: Codable, Equatable {
    let data: DashboardData
    let savedAt: Date
}

struct DashboardCacheSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let username: String?
    let generation: UInt64
    let profile: DashboardData?
    let profiles: [CachedDashboardProfile]
    let selectedPeriod: ProfilePeriod
    let autosubmit: AutosubmitStatus?
    let autosubmitObservedAt: Date?
    let fetchedAt: Date?
    let savedAt: Date

    init(
        profile: DashboardData?,
        autosubmit: AutosubmitStatus?,
        savedAt: Date,
        profiles: [CachedDashboardProfile] = [],
        selectedPeriod: ProfilePeriod = .all,
        schemaVersion: Int = currentSchemaVersion,
        username: String? = nil,
        generation: UInt64 = 0,
        fetchedAt: Date? = nil,
        autosubmitObservedAt: Date? = nil
    ) {
        let resolvedProfiles = profiles.isEmpty
            ? profile.map { [CachedDashboardProfile(data: $0, savedAt: savedAt)] } ?? []
            : profiles
        self.schemaVersion = schemaVersion
        self.username = username ?? profile?.username ?? resolvedProfiles.first?.data.username
        self.generation = generation
        self.profile = profile
        self.profiles = resolvedProfiles
        self.selectedPeriod = selectedPeriod
        self.autosubmit = autosubmit
        self.autosubmitObservedAt = autosubmitObservedAt
        self.fetchedAt = fetchedAt
        self.savedAt = savedAt
    }

    var isCompleteBatch: Bool {
        guard schemaVersion == Self.currentSchemaVersion, fetchedAt != nil,
              let username, !username.isEmpty else { return false }
        let mapped = profiles.reduce(into: [ProfilePeriod: DashboardData]()) {
            $0[$1.data.period] = $1.data
        }
        return profiles.count == ProfilePeriod.allCases.count
            && Set(mapped.keys) == Set(ProfilePeriod.allCases)
            && mapped.values.allSatisfy {
                $0.username.caseInsensitiveCompare(username) == .orderedSame
            }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, username, generation, profile, profiles, selectedPeriod
        case autosubmit, autosubmitObservedAt, fetchedAt, savedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported dashboard snapshot schema"
            )
        }
        let profile = try values.decodeIfPresent(DashboardData.self, forKey: .profile)
        let fetchedAt = try values.decodeIfPresent(Date.self, forKey: .fetchedAt)
        let savedAt = try values.decodeIfPresent(Date.self, forKey: .savedAt) ?? fetchedAt ?? Date.distantPast
        self.init(
            profile: profile,
            autosubmit: try values.decodeIfPresent(AutosubmitStatus.self, forKey: .autosubmit),
            savedAt: savedAt,
            profiles: try values.decodeIfPresent([CachedDashboardProfile].self, forKey: .profiles) ?? [],
            selectedPeriod: try values.decodeIfPresent(ProfilePeriod.self, forKey: .selectedPeriod) ?? .all,
            schemaVersion: schemaVersion,
            username: try values.decodeIfPresent(String.self, forKey: .username),
            generation: try values.decodeIfPresent(UInt64.self, forKey: .generation) ?? 0,
            fetchedAt: fetchedAt,
            autosubmitObservedAt: try values.decodeIfPresent(Date.self, forKey: .autosubmitObservedAt)
        )
    }
}

protocol DashboardCacheStoring {
    func load() -> DashboardCacheSnapshot?
    func save(_ snapshot: DashboardCacheSnapshot) throws
}

final class FileDashboardCacheStore: DashboardCacheStoring {
    private let fileManager: FileManager
    private let fileURL: URL
    private let legacyFileURL: URL?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        legacyFileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
            self.legacyFileURL = legacyFileURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.fileURL = applicationSupport
                .appendingPathComponent("com.youranreus.TokChan", isDirectory: true)
                .appendingPathComponent("dashboard-snapshot.json")
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            self.legacyFileURL = caches?
                .appendingPathComponent("com.youranreus.TokChan", isDirectory: true)
                .appendingPathComponent("dashboard-snapshot.json")
        }
    }

    func load() -> DashboardCacheSnapshot? {
        if let snapshot = decodeSnapshot(at: fileURL) { return snapshot }
        guard let legacyFileURL, legacyFileURL != fileURL else { return nil }
        return decodeSnapshot(at: legacyFileURL)
    }

    func save(_ snapshot: DashboardCacheSnapshot) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    private func decodeSnapshot(at url: URL) -> DashboardCacheSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(DashboardCacheSnapshot.self, from: data)
    }
}
