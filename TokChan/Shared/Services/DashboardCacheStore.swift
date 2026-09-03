import Foundation

struct DashboardCacheSnapshot: Codable, Equatable {
    let profile: DashboardData?
    let autosubmit: AutosubmitStatus?
    let savedAt: Date
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
