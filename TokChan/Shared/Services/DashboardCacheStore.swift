import Foundation

struct CachedDashboardProfile: Codable, Equatable {
    let data: DashboardData
    let savedAt: Date
}

struct DashboardCacheSnapshot: Codable, Equatable {
    let profile: DashboardData?
    let profiles: [CachedDashboardProfile]
    let selectedPeriod: ProfilePeriod
    let autosubmit: AutosubmitStatus?
    let savedAt: Date

    init(profile: DashboardData?, autosubmit: AutosubmitStatus?, savedAt: Date,
         profiles: [CachedDashboardProfile] = [], selectedPeriod: ProfilePeriod = .all) {
        self.profile = profile
        self.profiles = profiles.isEmpty ? profile.map { [CachedDashboardProfile(data: $0, savedAt: savedAt)] } ?? [] : profiles
        self.selectedPeriod = selectedPeriod
        self.autosubmit = autosubmit
        self.savedAt = savedAt
    }

    private enum CodingKeys: String, CodingKey {
        case profile, profiles, selectedPeriod, autosubmit, savedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let profile = try values.decodeIfPresent(DashboardData.self, forKey: .profile)
        let savedAt = try values.decode(Date.self, forKey: .savedAt)
        self.init(profile: profile,
                  autosubmit: try values.decodeIfPresent(AutosubmitStatus.self, forKey: .autosubmit),
                  savedAt: savedAt,
                  profiles: try values.decodeIfPresent([CachedDashboardProfile].self, forKey: .profiles) ?? [],
                  selectedPeriod: try values.decodeIfPresent(ProfilePeriod.self, forKey: .selectedPeriod) ?? .all)
    }
}

protocol DashboardCacheStoring {
    func load() -> DashboardCacheSnapshot?
    func save(_ snapshot: DashboardCacheSnapshot) throws
}

final class FileDashboardCacheStore: DashboardCacheStoring {
    private let fileManager: FileManager
    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.fileURL = baseURL
                .appendingPathComponent("com.youranreus.TokChan", isDirectory: true)
                .appendingPathComponent("dashboard-snapshot.json")
        }
    }

    func load() -> DashboardCacheSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(DashboardCacheSnapshot.self, from: data)
    }

    func save(_ snapshot: DashboardCacheSnapshot) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
