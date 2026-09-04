import Foundation

protocol NpxLocating {
    func locate(preferredPath: String?) -> URL?
}

struct NpxLocator: NpxLocating {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectory: URL
    private let systemCandidates: [URL]

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemCandidates: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/npx"),
            URL(fileURLWithPath: "/usr/local/bin/npx"),
            URL(fileURLWithPath: "/usr/bin/npx")
        ]
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.systemCandidates = systemCandidates
    }

    func locate(preferredPath: String?) -> URL? {
        if let preferredPath,
           !preferredPath.isEmpty,
           (preferredPath as NSString).isAbsolutePath {
            let preferred = URL(fileURLWithPath: preferredPath).standardizedFileURL
            if isExecutable(preferred) { return preferred }
        }

        var candidates = pathCandidates()
        candidates += systemCandidates
        candidates += selectedManagerCandidates()
        candidates += installedManagerCandidates()

        return deduplicated(candidates).first(where: isExecutable)
    }

    private func pathCandidates() -> [URL] {
        guard let path = environment["PATH"] else { return [] }
        return path.split(separator: ":").map {
            URL(fileURLWithPath: String($0), isDirectory: true)
                .appendingPathComponent("npx")
        }
    }

    private func selectedManagerCandidates() -> [URL] {
        var candidates: [URL] = []

        candidates += fnmRoots().map {
            $0.appendingPathComponent("aliases/default/bin/npx")
        }
        candidates += voltaRoots().map {
            $0.appendingPathComponent("bin/npx")
        }

        if let version = asdfHomeVersion() {
            candidates += asdfRoots().map {
                $0.appendingPathComponent("installs/nodejs/\(version)/bin/npx")
            }
        }

        candidates += nodenvRoots().compactMap { root in
            guard let version = exactVersion(in: root.appendingPathComponent("version")) else {
                return nil
            }
            return root.appendingPathComponent("versions/\(version)/bin/npx")
        }

        candidates += nPrefixes().map {
            $0.appendingPathComponent("bin/npx")
        }

        candidates += nvmRoots().compactMap { root in
            guard let version = resolvedNVMDefault(in: root) else { return nil }
            return root.appendingPathComponent("versions/node/v\(version.canonical)/bin/npx")
        }

        return candidates
    }

    private func installedManagerCandidates() -> [URL] {
        var candidates: [URL] = []

        for root in fnmRoots() {
            candidates += installedVersions(
                in: root.appendingPathComponent("node-versions"),
                executableSuffix: "installation/bin/npx"
            )
        }
        for root in asdfRoots() {
            candidates += installedVersions(
                in: root.appendingPathComponent("installs/nodejs"),
                executableSuffix: "bin/npx"
            )
        }
        for installsRoot in miseInstallsRoots() {
            candidates += installedVersions(
                in: installsRoot.appendingPathComponent("node"),
                executableSuffix: "bin/npx"
            )
        }
        for root in nodenvRoots() {
            candidates += installedVersions(
                in: root.appendingPathComponent("versions"),
                executableSuffix: "bin/npx"
            )
        }
        for root in nvmRoots() {
            candidates += installedVersions(
                in: root.appendingPathComponent("versions/node"),
                executableSuffix: "bin/npx"
            )
        }

        return candidates
    }

    private func fnmRoots() -> [URL] {
        var roots = environmentRoot("FNM_DIR").map { [$0] } ?? []
        if let xdgData = environmentRoot("XDG_DATA_HOME") {
            roots.append(xdgData.appendingPathComponent("fnm", isDirectory: true))
        } else {
            roots.append(homeDirectory.appendingPathComponent(".local/share/fnm", isDirectory: true))
        }
        roots += [
            homeDirectory.appendingPathComponent(".fnm", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Application Support/fnm", isDirectory: true)
        ]
        return deduplicated(roots)
    }

    private func voltaRoots() -> [URL] {
        deduplicated(
            (environmentRoot("VOLTA_HOME").map { [$0] } ?? []) +
            [homeDirectory.appendingPathComponent(".volta", isDirectory: true)]
        )
    }

    private func asdfRoots() -> [URL] {
        deduplicated(
            (environmentRoot("ASDF_DATA_DIR").map { [$0] } ?? []) +
            [homeDirectory.appendingPathComponent(".asdf", isDirectory: true)]
        )
    }

    private func miseInstallsRoots() -> [URL] {
        if let installsRoot = environmentRoot("MISE_INSTALLS_DIR") {
            return [installsRoot]
        }
        if let dataRoot = environmentRoot("MISE_DATA_DIR") {
            return [dataRoot.appendingPathComponent("installs", isDirectory: true)]
        }
        if let xdgData = environmentRoot("XDG_DATA_HOME") {
            return [xdgData.appendingPathComponent("mise/installs", isDirectory: true)]
        }
        return [homeDirectory.appendingPathComponent(".local/share/mise/installs", isDirectory: true)]
    }

    private func nodenvRoots() -> [URL] {
        deduplicated(
            (environmentRoot("NODENV_ROOT").map { [$0] } ?? []) +
            [homeDirectory.appendingPathComponent(".nodenv", isDirectory: true)]
        )
    }

    private func nPrefixes() -> [URL] {
        deduplicated(
            (environmentRoot("N_PREFIX").map { [$0] } ?? []) + [
                homeDirectory.appendingPathComponent("n", isDirectory: true),
                homeDirectory.appendingPathComponent(".n", isDirectory: true)
            ]
        )
    }

    private func nvmRoots() -> [URL] {
        var roots = environmentRoot("NVM_DIR").map { [$0] } ?? []
        if let xdgConfig = environmentRoot("XDG_CONFIG_HOME") {
            roots.append(xdgConfig.appendingPathComponent("nvm", isDirectory: true))
        }
        roots.append(homeDirectory.appendingPathComponent(".nvm", isDirectory: true))
        return deduplicated(roots)
    }

    private func environmentRoot(_ name: String) -> URL? {
        guard let value = environment[name],
              !value.isEmpty,
              !value.contains("\0"),
              (value as NSString).isAbsolutePath,
              !(value as NSString).pathComponents.contains("..") else {
            return nil
        }
        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    }

    private func asdfHomeVersion() -> String? {
        guard let text = boundedText(at: homeDirectory.appendingPathComponent(".tool-versions")) else {
            return nil
        }
        for line in text.split(whereSeparator: \Character.isNewline) {
            let components = line.split(whereSeparator: \Character.isWhitespace)
            guard components.first == "nodejs" else { continue }
            guard components.count == 2,
                  StrictSemanticVersion(String(components[1])) != nil else {
                return nil
            }
            return String(components[1])
        }
        return nil
    }

    private func exactVersion(in file: URL) -> String? {
        guard let token = exactToken(at: file), StrictSemanticVersion(token) != nil else {
            return nil
        }
        return token
    }

    private func resolvedNVMDefault(in root: URL) -> StrictSemanticVersion? {
        var alias = "default"
        var visited = Set<String>()

        for _ in 0..<8 {
            guard visited.insert(alias).inserted,
                  let token = exactToken(at: root.appendingPathComponent("alias/\(alias)")) else {
                return nil
            }
            if let version = StrictSemanticVersion(token) {
                return version
            }
            guard isSafeAlias(token) else { return nil }
            alias = token
        }
        return nil
    }

    private func exactToken(at file: URL) -> String? {
        guard let text = boundedText(at: file) else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              token.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace }) else {
            return nil
        }
        return token
    }

    private func boundedText(at file: URL) -> String? {
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 4_097) ?? Data()
            guard data.count <= 4_096 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func isSafeAlias(_ token: String) -> Bool {
        guard token != ".", token != "..", token.lowercased() != "system" else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return !token.isEmpty && token.unicodeScalars.allSatisfy(allowed.contains)
    }

    private func installedVersions(in directory: URL, executableSuffix: String) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.compactMap { entry -> (URL, StrictSemanticVersion)? in
            guard let version = StrictSemanticVersion(entry.lastPathComponent),
                  (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
                return nil
            }
            return (entry, version)
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.lastPathComponent < $1.0.lastPathComponent
        }
        .map { $0.0.appendingPathComponent(executableSuffix) }
    }

    private func deduplicated(_ urls: [URL]) -> [URL] {
        var paths = Set<String>()
        return urls.compactMap { url in
            let normalized = url.standardizedFileURL
            return paths.insert(normalized.path).inserted ? normalized : nil
        }
    }

    private func isExecutable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return fileManager.isExecutableFile(atPath: url.path)
    }
}

private struct StrictSemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let version = value.first == "v" || value.first == "V" ? String(value.dropFirst()) : value
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else { return nil }

        var numbers: [Int] = []
        for component in components {
            guard !component.isEmpty,
                  component.allSatisfy(\Character.isNumber),
                  (component.count == 1 || component.first != "0"),
                  let number = Int(component) else {
                return nil
            }
            numbers.append(number)
        }

        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }

    var canonical: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: StrictSemanticVersion, rhs: StrictSemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
