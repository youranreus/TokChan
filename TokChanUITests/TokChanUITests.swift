import XCTest

final class TokChanUITests: XCTestCase {
    func testApplicationLaunchesAndMenuBarPanelClosesAndReopens() throws {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-testing"]
        application.launch()
        defer { application.terminate() }

        XCTAssertNotEqual(application.state, .notRunning)

        let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let statusItem = systemUI.menuBars.statusItems["TokChan"]
        guard statusItem.waitForExistence(timeout: 10) else {
            throw XCTSkip("SystemUIServer did not expose menu bar items; run this UI test in isolation")
        }

        statusItem.click()
        let panel = application.otherElements["dashboard-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) {
            guard let counts = self.lifecycleCounts(of: panel) else { return false }
            return counts.appearances >= 1
        })

        statusItem.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !panel.exists })

        statusItem.click()
        let reopenedPanel = application.otherElements["dashboard-panel"]
        XCTAssertTrue(reopenedPanel.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) {
            guard let counts = self.lifecycleCounts(of: reopenedPanel) else { return false }
            return counts.appearances >= 2 && counts.disappearances >= 1
        })
    }

    func testRightClickShowsActionsWithoutOpeningDashboard() throws {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-testing"]
        application.launch()
        defer { application.terminate() }

        let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let statusItem = systemUI.menuBars.statusItems["TokChan"]
        guard statusItem.waitForExistence(timeout: 10) else {
            throw XCTSkip("SystemUIServer did not expose menu bar items; run this UI test in isolation")
        }

        statusItem.rightClick()
        XCTAssertFalse(application.otherElements["dashboard-panel"].exists)
        XCTAssertTrue(application.menuItems["提交并拉取"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.menuItems["拉取远程数据"].exists)
        XCTAssertFalse(application.menuItems["立刻推送"].exists)
        XCTAssertTrue(application.menuItems["设置…"].exists)
        XCTAssertTrue(application.menuItems["退出 TokChan"].exists)
    }

    func testSettingsOnlyAutosubmitTabHasAnApplyAction() throws {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-testing"]
        application.launch()
        defer { application.terminate() }

        let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let statusItem = systemUI.menuBars.statusItems["TokChan"]
        guard statusItem.waitForExistence(timeout: 10) else {
            throw XCTSkip("SystemUIServer did not expose menu bar items; run this UI test in isolation")
        }

        statusItem.rightClick()
        let settingsItem = application.menuItems["设置…"]
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 3))
        settingsItem.click()

        XCTAssertTrue(
            application.descendants(matching: .any)["settings-general-page"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(application.buttons["保存"].exists)
        XCTAssertFalse(application.buttons["apply-autosubmit-settings"].exists)
        XCTAssertTrue(application.buttons["cursor-login-button"].exists)

        let autosubmitTab = application.toolbars.buttons["自动提交"]
        XCTAssertTrue(autosubmitTab.waitForExistence(timeout: 3))
        autosubmitTab.click()
        XCTAssertTrue(application.buttons["apply-autosubmit-settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(application.buttons["保存"].exists)

        let aboutTab = application.toolbars.buttons["关于"]
        XCTAssertTrue(aboutTab.waitForExistence(timeout: 3))
        aboutTab.click()
        XCTAssertTrue(
            application.descendants(matching: .any)["settings-about-page"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(application.buttons["保存"].exists)
        XCTAssertFalse(application.buttons["apply-autosubmit-settings"].exists)
        let updateButton = application.buttons["check-for-updates"]
        XCTAssertTrue(updateButton.exists)
        XCTAssertTrue(updateButton.isEnabled)
        updateButton.click()
        XCTAssertFalse(updateButton.isEnabled)
    }

    func testCheckForUpdatesIsDisabledWhileUpdaterIsBusy() throws {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-testing", "--updater-busy"]
        application.launch()
        defer { application.terminate() }

        let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let statusItem = systemUI.menuBars.statusItems["TokChan"]
        guard statusItem.waitForExistence(timeout: 10) else {
            throw XCTSkip("SystemUIServer did not expose menu bar items; run this UI test in isolation")
        }
        statusItem.rightClick()
        application.menuItems["设置…"].click()
        let aboutTab = application.toolbars.buttons["关于"]
        XCTAssertTrue(aboutTab.waitForExistence(timeout: 5))
        aboutTab.click()
        let button = application.buttons["check-for-updates"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        XCTAssertFalse(button.isEnabled)
    }

    private func lifecycleCounts(of panel: XCUIElement) -> (appearances: Int, disappearances: Int)? {
        guard let value = panel.value as? String else { return nil }
        let components = value.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return nil }
        return (components[0], components[1])
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
