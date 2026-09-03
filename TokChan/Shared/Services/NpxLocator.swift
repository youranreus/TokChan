import Foundation

protocol NpxLocating {
    func locate(preferredPath: String?) -> URL?
}

struct NpxLocator: NpxLocating {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectory: URL

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func locate(preferredPath: String?) -> URL? {
        if let preferredPath,
           !preferredPath.isEmpty,
           (preferredPath as NSString).isAbsolutePath {
            let preferred = URL(fileURLWithPath: preferredPath)
            if isExecutable(preferred) { return preferred }
        }

        var candidates: [URL] = []
        if let path = environment["PATH"] {
            candidates += path.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent("npx")
            }
        }

        candidates += [
            URL(fileURLWithPath: "/opt/homebrew/bin/npx"),
            URL(fileURLWithPath: "/usr/local/bin/npx"),
            URL(fileURLWithPath: "/usr/bin/npx")
        ]

        let nodeVersions = homeDirectory
            .appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let versions = try? fileManager.contentsOfDirectory(
            at: nodeVersions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            candidates += versions
                .sorted { Self.isNewerNodeVersion($0.lastPathComponent, than: $1.lastPathComponent) }
                .map { $0.appendingPathComponent("bin/npx") }
        }

        return candidates.first(where: isExecutable)
    }

    private func isExecutable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return fileManager.isExecutableFile(atPath: url.path)
    }

    private static func nodeVersion(_ directoryName: String) -> [Int] {
        directoryName
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .prefix(3)
            .map { Int($0) ?? 0 }
    }

    private static func isNewerNodeVersion(_ lhs: String, than rhs: String) -> Bool {
        let left = nodeVersion(lhs) + Array(repeating: 0, count: 3)
        let right = nodeVersion(rhs) + Array(repeating: 0, count: 3)
        for index in 0..<3 where left[index] != right[index] {
            return left[index] > right[index]
        }
        return lhs > rhs
    }
}
