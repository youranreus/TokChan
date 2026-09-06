import XCTest
@testable import TokChan

final class AboutCopyTests: XCTestCase {
    func testAboutCopyAndAuthorDestinationAreExact() {
        XCTAssertEqual(AboutCopy.summary, "Tokscale的状态栏预览应用")
        XCTAssertEqual(AboutCopy.bylinePrefix + AboutCopy.author, "Made with love by 季悠然")
        XCTAssertEqual(AboutCopy.authorURL.absoluteString, "https://blog.mitsuha.space")
    }
}
