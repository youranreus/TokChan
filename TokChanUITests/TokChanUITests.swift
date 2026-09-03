import XCTest

final class TokChanUITests: XCTestCase {
    func testApplicationLaunches() {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-testing"]
        application.launch()

        XCTAssertNotEqual(application.state, .notRunning)
    }
}
