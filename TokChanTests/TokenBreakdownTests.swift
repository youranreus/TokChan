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
        XCTAssertNil(ClientIcon.assetName(for: "new-unknown-client"))
        XCTAssertEqual(ClientIcon.knownClients.count, 31)
        for client in ClientIcon.knownClients {
            XCTAssertNotNil(NSImage(named: "client-\(client)"), "Missing bundled client \(client)")
        }
    }
}
