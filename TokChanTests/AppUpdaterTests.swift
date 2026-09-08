import Combine
import XCTest
@testable import TokChan

@MainActor
final class AppUpdaterTests: XCTestCase {
    func testCheckForUpdatesForwardsWhenAvailable() {
        var checks = 0
        let updater = AppUpdater(canCheckForUpdates: true) { checks += 1 }

        updater.checkForUpdates()
        updater.checkForUpdates()

        XCTAssertEqual(checks, 1)
        XCTAssertFalse(updater.canCheckForUpdates)
    }

    func testCheckForUpdatesRejectsDuplicateWhileBusyAndRecovers() {
        let availability = CurrentValueSubject<Bool, Never>(true)
        var checks = 0
        let updater = AppUpdater(
            canCheckForUpdates: true,
            checkAction: { checks += 1 },
            availability: availability.eraseToAnyPublisher()
        )

        availability.send(false)
        XCTAssertFalse(updater.canCheckForUpdates)
        updater.checkForUpdates()
        XCTAssertEqual(checks, 0)

        availability.send(true)
        XCTAssertTrue(updater.canCheckForUpdates)
        updater.checkForUpdates()
        XCTAssertEqual(checks, 1)
    }
}
