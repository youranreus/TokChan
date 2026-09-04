import Foundation
import XCTest
@testable import TokChan

final class NpxLocatorTests: XCTestCase {
    func testExecutablePreferredPathTakesPrecedenceOverDiscovery() throws {
        try withTemporaryRoot { root in
            let preferred = root.appendingPathComponent("custom/npx")
            let pathNpx = root.appendingPathComponent("path/npx")
            try makeExecutable(at: preferred)
            try makeExecutable(at: pathNpx)

            XCTAssertEqual(
                locator(root, environment: ["PATH": pathNpx.deletingLastPathComponent().path])
                    .locate(preferredPath: preferred.path),
                preferred
            )
        }
    }

    func testInvalidOrRelativePreferredPathFallsBackToPATH() throws {
        try withTemporaryRoot { root in
            let pathNpx = root.appendingPathComponent("path/npx")
            try makeExecutable(at: pathNpx)
            let locator = locator(root, environment: ["PATH": pathNpx.deletingLastPathComponent().path])

            XCTAssertEqual(locator.locate(preferredPath: root.appendingPathComponent("missing/npx").path), pathNpx)
            XCTAssertEqual(locator.locate(preferredPath: "bin/npx"), pathNpx)
        }
    }

    func testPATHPrecedesFixedSystemAndManagerCandidates() throws {
        try withTemporaryRoot { root in
            let pathNpx = root.appendingPathComponent("path/bin/npx")
            let systemNpx = root.appendingPathComponent("homebrew/bin/npx")
            let fnmNpx = root.appendingPathComponent(".local/share/fnm/aliases/default/bin/npx")
            try [pathNpx, systemNpx, fnmNpx].forEach(makeExecutable)

            let locator = NpxLocator(
                environment: ["PATH": pathNpx.deletingLastPathComponent().path],
                homeDirectory: root,
                systemCandidates: [systemNpx]
            )
            XCTAssertEqual(locator.locate(preferredPath: nil), pathNpx)
        }
    }

    func testFixedSystemCandidatePrecedesManagerCandidates() throws {
        try withTemporaryRoot { root in
            let systemNpx = root.appendingPathComponent("homebrew/bin/npx")
            let fnmNpx = root.appendingPathComponent(".local/share/fnm/aliases/default/bin/npx")
            try makeExecutable(at: systemNpx)
            try makeExecutable(at: fnmNpx)

            XCTAssertEqual(
                NpxLocator(environment: [:], homeDirectory: root, systemCandidates: [systemNpx])
                    .locate(preferredPath: nil),
                systemNpx
            )
        }
    }

    func testFindsEveryManagerDefaultLayout() throws {
        let relativeCandidates = [
            ".local/share/fnm/node-versions/v20.1.0/installation/bin/npx",
            ".fnm/node-versions/v20.1.0/installation/bin/npx",
            "Library/Application Support/fnm/node-versions/v20.1.0/installation/bin/npx",
            ".volta/bin/npx",
            ".asdf/installs/nodejs/20.1.0/bin/npx",
            ".local/share/mise/installs/node/20.1.0/bin/npx",
            ".nodenv/versions/20.1.0/bin/npx",
            "n/bin/npx",
            ".n/bin/npx",
            ".nvm/versions/node/v20.1.0/bin/npx"
        ]

        for relativePath in relativeCandidates {
            try withTemporaryRoot { root in
                let expected = root.appendingPathComponent(relativePath)
                try makeExecutable(at: expected)
                XCTAssertEqual(
                    locator(root).locate(preferredPath: nil),
                    expected,
                    "Failed to discover default layout: \(relativePath)"
                )
            }
        }
    }

    func testFindsEveryAbsoluteManagerRootOverride() throws {
        let cases: [(String, String, String)] = [
            ("FNM_DIR", "custom-fnm", "node-versions/v20.1.0/installation/bin/npx"),
            ("VOLTA_HOME", "custom-volta", "bin/npx"),
            ("ASDF_DATA_DIR", "custom-asdf", "installs/nodejs/20.1.0/bin/npx"),
            ("MISE_INSTALLS_DIR", "custom-mise-installs", "node/20.1.0/bin/npx"),
            ("MISE_DATA_DIR", "custom-mise-data", "installs/node/20.1.0/bin/npx"),
            ("NODENV_ROOT", "custom-nodenv", "versions/20.1.0/bin/npx"),
            ("N_PREFIX", "custom-n", "bin/npx"),
            ("NVM_DIR", "custom-nvm", "versions/node/v20.1.0/bin/npx")
        ]

        for (variable, rootName, suffix) in cases {
            try withTemporaryRoot { home in
                let managerRoot = home.appendingPathComponent(rootName, isDirectory: true)
                let expected = managerRoot.appendingPathComponent(suffix)
                try makeExecutable(at: expected)
                XCTAssertEqual(
                    locator(home, environment: [variable: managerRoot.path]).locate(preferredPath: nil),
                    expected,
                    "Failed to honor \(variable)"
                )
            }
        }
    }

    func testFindsXDGManagerRoots() throws {
        try withTemporaryRoot { home in
            let data = home.appendingPathComponent("xdg-data", isDirectory: true)
            let fnm = data.appendingPathComponent("fnm/node-versions/v21.2.3/installation/bin/npx")
            try makeExecutable(at: fnm)
            XCTAssertEqual(
                locator(home, environment: ["XDG_DATA_HOME": data.path]).locate(preferredPath: nil),
                fnm
            )
        }

        try withTemporaryRoot { home in
            let config = home.appendingPathComponent("xdg-config", isDirectory: true)
            let nvm = config.appendingPathComponent("nvm/versions/node/v21.2.3/bin/npx")
            try makeExecutable(at: nvm)
            XCTAssertEqual(
                locator(home, environment: ["XDG_CONFIG_HOME": config.path]).locate(preferredPath: nil),
                nvm
            )
        }
    }

    func testFNMDefaultAliasPrecedesNewerInstallation() throws {
        try withTemporaryRoot { root in
            let fnm = root.appendingPathComponent(".local/share/fnm", isDirectory: true)
            let selectedInstallation = fnm.appendingPathComponent("node-versions/v20.1.0/installation", isDirectory: true)
            let selected = selectedInstallation.appendingPathComponent("bin/npx")
            let newer = fnm.appendingPathComponent("node-versions/v22.0.0/installation/bin/npx")
            try makeExecutable(at: selected)
            try makeExecutable(at: newer)
            try FileManager.default.createDirectory(
                at: fnm.appendingPathComponent("aliases"),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                at: fnm.appendingPathComponent("aliases/default"),
                withDestinationURL: selectedInstallation
            )

            XCTAssertEqual(
                locator(root).locate(preferredPath: nil),
                fnm.appendingPathComponent("aliases/default/bin/npx")
            )
        }
    }

    func testBrokenFNMDefaultAliasFallsBackToNewestInstallation() throws {
        try withTemporaryRoot { root in
            let fnm = root.appendingPathComponent(".local/share/fnm", isDirectory: true)
            let fallback = fnm.appendingPathComponent("node-versions/v22.0.0/installation/bin/npx")
            try makeExecutable(at: fallback)
            try FileManager.default.createDirectory(
                at: fnm.appendingPathComponent("aliases"),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                at: fnm.appendingPathComponent("aliases/default"),
                withDestinationURL: fnm.appendingPathComponent("missing")
            )

            XCTAssertEqual(locator(root).locate(preferredPath: nil), fallback)
        }
    }

    func testStableManagerSelectionPrecedesInstalledFallbacks() throws {
        try withTemporaryRoot { root in
            let fnmFallback = root.appendingPathComponent(
                ".local/share/fnm/node-versions/v99.0.0/installation/bin/npx"
            )
            let volta = root.appendingPathComponent(".volta/bin/npx")
            try makeExecutable(at: fnmFallback)
            try makeExecutable(at: volta)

            XCTAssertEqual(locator(root).locate(preferredPath: nil), volta)
        }
    }

    func testASDFHomeToolVersionSelectsOlderExactInstallation() throws {
        try withTemporaryRoot { root in
            let selected = root.appendingPathComponent(".asdf/installs/nodejs/20.1.0/bin/npx")
            let newer = root.appendingPathComponent(".asdf/installs/nodejs/22.0.0/bin/npx")
            try makeExecutable(at: selected)
            try makeExecutable(at: newer)
            try makeText("nodejs 20.1.0\n", at: root.appendingPathComponent(".tool-versions"))

            XCTAssertEqual(locator(root).locate(preferredPath: nil), selected)
        }
    }

    func testNodenvGlobalVersionSelectsOlderExactInstallation() throws {
        try withTemporaryRoot { root in
            let selected = root.appendingPathComponent(".nodenv/versions/20.1.0/bin/npx")
            let newer = root.appendingPathComponent(".nodenv/versions/22.0.0/bin/npx")
            try makeExecutable(at: selected)
            try makeExecutable(at: newer)
            try makeText("20.1.0\n", at: root.appendingPathComponent(".nodenv/version"))

            XCTAssertEqual(locator(root).locate(preferredPath: nil), selected)
        }
    }

    func testNVMDefaultSupportsExactVersionAndBoundedAliasChain() throws {
        try withTemporaryRoot { root in
            let selected = root.appendingPathComponent(".nvm/versions/node/v20.1.0/bin/npx")
            let newer = root.appendingPathComponent(".nvm/versions/node/v22.0.0/bin/npx")
            try makeExecutable(at: selected)
            try makeExecutable(at: newer)
            try makeText("team\n", at: root.appendingPathComponent(".nvm/alias/default"))
            try makeText("v20.1.0\n", at: root.appendingPathComponent(".nvm/alias/team"))

            XCTAssertEqual(locator(root).locate(preferredPath: nil), selected)
        }
    }

    func testNVMRejectsTraversalAliasesAndCycles() throws {
        let aliasFiles = [
            ["default": "../redirect\n", "redirect": "20.1.0\n"],
            ["default": "team\n", "team": "default\n"]
        ]

        for aliases in aliasFiles {
            try withTemporaryRoot { root in
                let selectedIfUnsafe = root.appendingPathComponent(".nvm/versions/node/v20.1.0/bin/npx")
                let fallback = root.appendingPathComponent(".nvm/versions/node/v22.0.0/bin/npx")
                try makeExecutable(at: selectedIfUnsafe)
                try makeExecutable(at: fallback)
                for (name, contents) in aliases {
                    try makeText(contents, at: root.appendingPathComponent(".nvm/alias/\(name)"))
                }
                if aliases["default"] == "../redirect\n" {
                    try makeText("20.1.0\n", at: root.appendingPathComponent(".nvm/redirect"))
                }

                XCTAssertEqual(locator(root).locate(preferredPath: nil), fallback)
            }
        }
    }

    func testUnsafeOrAmbiguousSelectionTextFallsBackToNewestVersion() throws {
        let cases: [(String, String)] = [
            (".tool-versions", "nodejs path:../../evil\n"),
            (".nodenv/version", "system\n"),
            (".nvm/alias/default", "lts/*\n")
        ]

        for (configPath, contents) in cases {
            try withTemporaryRoot { root in
                let fallback: URL
                if configPath == ".tool-versions" {
                    fallback = root.appendingPathComponent(".asdf/installs/nodejs/22.0.0/bin/npx")
                } else if configPath == ".nodenv/version" {
                    fallback = root.appendingPathComponent(".nodenv/versions/22.0.0/bin/npx")
                } else {
                    fallback = root.appendingPathComponent(".nvm/versions/node/v22.0.0/bin/npx")
                }
                try makeExecutable(at: fallback)
                try makeText(contents, at: root.appendingPathComponent(configPath))

                XCTAssertEqual(locator(root).locate(preferredPath: nil), fallback)
            }
        }
    }

    func testStrictSemanticVersionFallbackRejectsMalformedAndPrereleaseDirectories() throws {
        try withTemporaryRoot { root in
            let base = root.appendingPathComponent(".local/share/fnm/node-versions")
            let expected = base.appendingPathComponent("v22.3.0/installation/bin/npx")
            try makeExecutable(at: base.appendingPathComponent("v9.9.9/installation/bin/npx"))
            try makeExecutable(at: expected)
            try makeText(
                "not executable",
                at: base.appendingPathComponent("v23.0.0/installation/bin/npx")
            )
            try makeExecutable(at: base.appendingPathComponent("v99/installation/bin/npx"))
            try makeExecutable(at: base.appendingPathComponent("v99.0.0-rc.1/installation/bin/npx"))
            try makeExecutable(at: base.appendingPathComponent("v099.0.0/installation/bin/npx"))
            try makeExecutable(at: base.appendingPathComponent("garbage.100.100/installation/bin/npx"))

            XCTAssertEqual(locator(root).locate(preferredPath: nil), expected)
        }
    }

    func testInstalledFallbackManagerOrderIsDeterministic() throws {
        try withTemporaryRoot { root in
            let fnm = root.appendingPathComponent(
                ".local/share/fnm/node-versions/v18.0.0/installation/bin/npx"
            )
            let asdf = root.appendingPathComponent(".asdf/installs/nodejs/99.0.0/bin/npx")
            let mise = root.appendingPathComponent(".local/share/mise/installs/node/100.0.0/bin/npx")
            try makeExecutable(at: fnm)
            try makeExecutable(at: asdf)
            try makeExecutable(at: mise)

            XCTAssertEqual(locator(root).locate(preferredPath: nil), fnm)
        }
    }

    func testRelativeAndTraversalShapedEnvironmentRootsAreIgnored() throws {
        let cases = [
            ("FNM_DIR", "node-versions/v20.1.0/installation/bin/npx"),
            ("VOLTA_HOME", "bin/npx"),
            ("ASDF_DATA_DIR", "installs/nodejs/20.1.0/bin/npx"),
            ("MISE_INSTALLS_DIR", "node/20.1.0/bin/npx"),
            ("MISE_DATA_DIR", "installs/node/20.1.0/bin/npx"),
            ("NODENV_ROOT", "versions/20.1.0/bin/npx"),
            ("N_PREFIX", "bin/npx"),
            ("NVM_DIR", "versions/node/v20.1.0/bin/npx"),
            ("XDG_DATA_HOME", "fnm/node-versions/v20.1.0/installation/bin/npx"),
            ("XDG_CONFIG_HOME", "nvm/versions/node/v20.1.0/bin/npx")
        ]

        for (variable, suffix) in cases {
            try withTemporaryRoot { root in
                let outside = root.appendingPathComponent("outside/\(suffix)")
                try makeExecutable(at: outside)
                let traversal = root.path + "/inside/../outside"

                XCTAssertNil(locator(root, environment: [variable: "relative/root"]).locate(preferredPath: nil))
                XCTAssertNil(locator(root, environment: [variable: traversal]).locate(preferredPath: nil))
            }
        }
    }

    func testExcludedShimsMultishellAndCachesAreNeverCandidates() throws {
        try withTemporaryRoot { root in
            let excluded = [
                ".local/state/fnm_multishells/session/bin/npx",
                ".asdf/shims/npx",
                ".local/share/mise/shims/npx",
                ".local/share/mise/installs/node/latest/bin/npx",
                ".nodenv/shims/npx",
                "n/n/versions/node/20.1.0/bin/npx",
                ".volta/tools/image/node/20.1.0/bin/npx"
            ]
            for path in excluded {
                try makeExecutable(at: root.appendingPathComponent(path))
            }

            XCTAssertNil(locator(root).locate(preferredPath: nil))
        }
    }

    func testDirectoryAndNonExecutableCandidatesAreRejected() throws {
        try withTemporaryRoot { root in
            let directory = root.appendingPathComponent(
                ".local/share/fnm/node-versions/v22.0.0/installation/bin/npx",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try makeText("not executable", at: root.appendingPathComponent(".volta/bin/npx"))

            XCTAssertNil(locator(root).locate(preferredPath: nil))
        }
    }

    func testReturnsNilWhenNoCandidateIsExecutable() throws {
        try withTemporaryRoot { root in
            XCTAssertNil(locator(root).locate(preferredPath: nil))
        }
    }

    private func locator(_ root: URL, environment: [String: String] = [:]) -> NpxLocator {
        NpxLocator(environment: environment, homeDirectory: root, systemCandidates: [])
    }

    private func withTemporaryRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChanNpxLocatorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeText(_ contents: String, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
