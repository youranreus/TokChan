import AppKit
import XCTest
@testable import TokChan

final class TokenBreakdownTests: XCTestCase {
    func testFractionsMatchFiveCategoriesAndSumToOne() {
        let breakdown = TokenBreakdown(input: 10, output: 5, cacheRead: 80, cacheWrite: 3, reasoning: 2)
        XCTAssertEqual(breakdown.fraction(for: .cacheRead), 0.8, accuracy: 0.0001)
        XCTAssertEqual(TokenCategory.allCases.reduce(0) { $0 + breakdown.fraction(for: $1) }, 1, accuracy: 0.0001)
    }

    func testZeroAndInvalidComponentsProduceSafeWidths() {
        let empty = TokenBreakdown()
        XCTAssertTrue(TokenCategory.allCases.allSatisfy { empty.fraction(for: $0) == 0 })
        let malformed = TokenBreakdown(input: .infinity, output: -3, cacheRead: .nan, cacheWrite: 5)
        XCTAssertEqual(malformed.fraction(for: .cacheWrite), 1)
        XCTAssertEqual(malformed.value(for: .output), 0)
        let huge = TokenBreakdown(input: .greatestFiniteMagnitude, output: .greatestFiniteMagnitude)
        XCTAssertEqual(huge.fraction(for: .input), 0.5, accuracy: 0.0001)
    }

    func testEveryClientAssetCanBeLoadedFromApplicationBundle() {
        XCTAssertEqual(ClientIcon.assetName(for: "codex"), "client-openai")
        XCTAssertEqual(ClientIcon.assetName(for: "kilo"), "client-kilocode")
        XCTAssertEqual(ClientIcon.assetName(for: "codebuddy"), "client-codebuddy")
        XCTAssertNotEqual(ClientIcon.assetName(for: "codebuddy"), "client-codebuff")
        XCTAssertEqual(ClientIcon.assetName(for: "devin"), "client-devin")
        XCTAssertEqual(ClientIcon.assetName(for: "sakana"), "client-sakana")
        XCTAssertNil(ClientIcon.assetName(for: "new-unknown-client"))
        let expectedTokscaleClientIDs: Set<String> = [
            "9router", "amp", "antigravity", "antigravity-cli", "augment",
            "cherrystudio", "claude", "cline", "codebuddy", "codebuff", "codex",
            "commandcode", "copilot", "crush", "cursor", "devin-cli", "devin-desktop",
            "droid", "dsh", "freebuff", "fx", "gemini", "gjc", "goose", "grok",
            "hermes", "hindsight", "jcode", "junie", "kilocode", "kimchi", "kimi",
            "kiro", "kilo", "lmstudio", "mcode", "micode", "mux", "omp",
            "openclaw", "opencode", "opencodereview", "pi", "prime-agent", "qwen",
            "reasonix", "roocode", "senpi", "synthetic", "trae", "unsloth", "warp",
            "workbuddy", "zcode", "zed",
        ]
        XCTAssertEqual(ClientIcon.tokscaleClientIDs, expectedTokscaleClientIDs)
        XCTAssertEqual(ClientIcon.tokscaleClientIDs.count, 55)
        XCTAssertTrue(ClientIcon.tokscaleClientIDs.isSubset(of: ClientIcon.knownClients))
        for clientID in ClientIcon.tokscaleClientIDs {
            guard let assetName = ClientIcon.assetName(for: clientID) else {
                XCTFail("Missing mapping for Tokscale client \(clientID)")
                continue
            }
            XCTAssertNotNil(NSImage(named: assetName), "Missing bundled asset \(assetName) for \(clientID)")
        }
    }
}
