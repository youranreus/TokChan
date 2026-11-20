import AppKit
import XCTest

final class TokChanUITests: XCTestCase {
    func testHoverPinDragAndReleaseEdgeDashboard() throws {
        try verifyEdgeDashboard(arguments: ["--ui-testing", "--edge-panel"])
    }

    func testHoverPinDragAndReleaseGlassDashboard() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Liquid Glass requires macOS 26") }
        try verifyEdgeDashboard(arguments: ["--ui-testing", "--edge-panel", "--liquid-glass"])
    }

    private func verifyEdgeDashboard(arguments: [String]) throws {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        try XCTSkipIf(session?["CGSSessionScreenIsLocked"] as? Bool == true, "Pointer hover requires an unlocked desktop")
        let application = XCUIApplication()
        application.launchArguments = arguments
        application.launch()
        defer { application.terminate() }

        // A collapsed panel is only seven points wide and may be omitted from the AX tree.
        // WindowServer geometry lets us exercise the same hover target the user sees.
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("TokChan.app")
        let testedApp = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.youranreus.TokChan")
            .first { $0.bundleURL?.standardizedFileURL == appURL.standardizedFileURL })
        func panelFrame() -> CGRect? {
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            let windows = info as? [[CFString: Any]] ?? []
            for window in windows where window[kCGWindowOwnerPID] as? Int32 == testedApp.processIdentifier {
                guard window[kCGWindowLayer] as? Int == Int(CGWindowLevelForKey(.floatingWindow)),
                      let bounds = window[kCGWindowBounds] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: bounds) else { continue }
                return frame
            }
            return nil
        }
        let icon = application.menuBars.statusItems["TokChan"].firstMatch
        let origin = icon.coordinate(withNormalizedOffset: .zero)
        func coordinate(at point: CGPoint) -> XCUICoordinate {
            let start = origin.screenPoint
            return origin.withOffset(CGVector(dx: point.x - start.x, dy: point.y - start.y))
        }

        XCTAssertTrue(waitUntil(timeout: 5) { panelFrame() != nil })
        let initialFrame = try XCTUnwrap(panelFrame())
        let initialPoint = CGPoint(x: initialFrame.midX, y: initialFrame.midY)
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        XCTAssertEqual(CGGetDisplaysWithPoint(initialPoint, 1, &displayID, &count), .success)
        XCTAssertEqual(count, 1)
        let screen = try XCTUnwrap(NSScreen.screens.first {
            ($0.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        })
        // WindowServer and XCTest measure Y downward; AppKit's visibleFrame measures upward.
        let display = CGDisplayBounds(displayID)
        let visibleTop = display.minY + screen.frame.maxY - screen.visibleFrame.maxY
        let visibleLeft = display.minX + screen.visibleFrame.minX - screen.frame.minX
        let visibleRight = visibleLeft + screen.visibleFrame.width
        let outside = CGPoint(x: visibleLeft + 1, y: initialPoint.y)
        coordinate(at: outside).hover()
        XCTAssertTrue(waitUntil(timeout: 5) { panelFrame()?.width == 7 })
        let tab = try XCTUnwrap(panelFrame())
        let handle = CGPoint(x: tab.midX, y: tab.midY)
        coordinate(at: handle).hover()
        XCTAssertTrue(waitUntil(timeout: 5) {
            guard let frame = panelFrame() else { return false }
            return frame.width > 100 && abs(frame.maxX - (visibleRight - 8)) < 1
        })
        let full = try XCTUnwrap(panelFrame())
        XCTAssertEqual(tab.maxX - full.maxX, 8, accuracy: 1)
        // Stay in the original strip past the automatic-dismissal delay, then cross the
        // gap into content. The panel must remain expanded for this entire transfer.
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (panelFrame()?.width ?? 0) < full.width - 1
        }, object: nil)
        collapsed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 1.2), .completed)
        coordinate(at: CGPoint(x: full.maxX - 18, y: full.midY)).hover()
        let pin = application.buttons["edge-panel-pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.click()
        if arguments.contains("--liquid-glass") {
            XCTAssertTrue(waitUntil(timeout: 4) {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == testedApp.processIdentifier
            })
        }
        coordinate(at: outside).hover()
        XCTAssertEqual(pin.label, "解除固定")
        XCTAssertTrue(application.buttons["submit-refresh-button"].exists)

        let grabY = 14.0
        let grip = CGPoint(x: full.minX + 26, y: full.minY + grabY)
        let travel = screen.visibleFrame.height - 16 - full.height
        let release = CGPoint(x: visibleLeft + 2, y: visibleTop + 8 + max(0, travel) * 0.3 + grabY)
        coordinate(at: grip).click(forDuration: 0.2, thenDragTo: coordinate(at: release))
        XCTAssertTrue(waitUntil(timeout: 5) {
            guard let frame = panelFrame() else { return false }
            return abs(frame.minX - (visibleLeft + 8)) <= 2
        })
        let docked = try XCTUnwrap(panelFrame())
        XCTAssertEqual(docked.minX, visibleLeft + 8, accuracy: 2)
        XCTAssertEqual(docked.minY + grabY, release.y, accuracy: 2)
        pin.click()
        coordinate(at: CGPoint(x: visibleRight - 2, y: docked.midY)).hover()
        XCTAssertTrue(waitUntil(timeout: 5) { panelFrame()?.width == 7 })
        let edge = try XCTUnwrap(panelFrame())
        XCTAssertEqual(edge.minX, visibleLeft, accuracy: 1)
        XCTAssertEqual(edge.minY, docked.minY, accuracy: 1)
        XCTAssertEqual(edge.height, docked.height, accuracy: 1)
    }

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

    func testTypingEdgePeekWidthInDisplaySettings() throws {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-testing", "--edge-panel"]
        application.launch()
        defer { application.terminate() }
        application.menuBars.statusItems["TokChan"].firstMatch.rightClick()
        application.menuItems["设置…"].click()
        let display = application.toolbars.buttons["展示配置"]
        display.click()
        let width = application.textFields["edge-peek-width"]
        XCTAssertTrue(width.waitForExistence(timeout: 3))
        width.click()
        width.typeKey("a", modifierFlags: .command)
        width.typeKey("3", modifierFlags: [])
        XCTAssertEqual(width.value as? String, "3")
        width.typeKey("2", modifierFlags: [])
        XCTAssertEqual(width.value as? String, "32")
        width.typeKey(.return, modifierFlags: [])
        application.toolbars.buttons["常规"].click()
        display.click()
        XCTAssertEqual(width.value as? String, "32")
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

        let displayTab = application.toolbars.buttons["展示配置"]
        XCTAssertTrue(displayTab.waitForExistence(timeout: 3))
        displayTab.click()
        XCTAssertTrue(
            application.descendants(matching: .any)["settings-display-page"]
                .waitForExistence(timeout: 3)
        )
        let hideZeroCostModels = application.switches["hide-zero-cost-models"]
        let hiddenClientsEnabled = application.switches["hidden-clients-enabled"]
        XCTAssertTrue(hideZeroCostModels.exists)
        XCTAssertTrue(hiddenClientsEnabled.exists)

        let periodPicker = application.popUpButtons["default-period"]
        XCTAssertTrue(periodPicker.waitForExistence(timeout: 3))
        XCTAssertEqual(periodPicker.value as? String, "日")

        func selectPeriodFromMenu(_ title: String) -> Bool {
            periodPicker.click()
            let item = application.menuItems[title]
            guard item.waitForExistence(timeout: 3) else { return false }
            item.click()
            return waitUntil(timeout: 3) { periodPicker.value as? String == title }
        }
        XCTAssertTrue(selectPeriodFromMenu("周"))
        XCTAssertTrue(selectPeriodFromMenu("日"))
        if isToggleOn(hideZeroCostModels) {
            hideZeroCostModels.click()
            XCTAssertTrue(waitUntil(timeout: 3) { !self.isToggleOn(hideZeroCostModels) })
        }
        hideZeroCostModels.click()
        XCTAssertTrue(waitUntil(timeout: 3) { self.isToggleOn(hideZeroCostModels) })

        if isToggleOn(hiddenClientsEnabled) {
            hiddenClientsEnabled.click()
            XCTAssertTrue(waitUntil(timeout: 3) { !self.isToggleOn(hiddenClientsEnabled) })
        }
        XCTAssertFalse(application.switches["hidden-client-codex"].exists)
        hiddenClientsEnabled.click()
        XCTAssertTrue(waitUntil(timeout: 3) { self.isToggleOn(hiddenClientsEnabled) })

        let codexSelection = application.switches["hidden-client-codex"]
        XCTAssertTrue(codexSelection.waitForExistence(timeout: 3))
        if isToggleOn(codexSelection) {
            codexSelection.click()
            XCTAssertTrue(waitUntil(timeout: 3) { !self.isToggleOn(codexSelection) })
        }
        codexSelection.click()
        XCTAssertTrue(waitUntil(timeout: 3) { self.isToggleOn(codexSelection) })

        hiddenClientsEnabled.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !self.isToggleOn(hiddenClientsEnabled) })
        XCTAssertTrue(waitUntil(timeout: 3) { !codexSelection.exists })

        hiddenClientsEnabled.click()
        XCTAssertTrue(waitUntil(timeout: 3) { self.isToggleOn(hiddenClientsEnabled) })
        XCTAssertTrue(codexSelection.waitForExistence(timeout: 3))
        XCTAssertTrue(self.isToggleOn(codexSelection))
        XCTAssertFalse(application.buttons["保存"].exists)
        XCTAssertFalse(application.buttons["apply-autosubmit-settings"].exists)

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

    func testCursorSyncToggleSavesWithoutApplyAndSurvivesSettingsReopen() throws {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-testing"]
        application.launch()
        defer { application.terminate() }
        let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let statusItem = systemUI.menuBars.statusItems["TokChan"]
        guard statusItem.waitForExistence(timeout: 10) else {
            throw XCTSkip("SystemUIServer did not expose menu bar items; Cursor sync Settings gate unverified")
        }
        statusItem.rightClick()
        application.menuItems["设置…"].click()
        let toggle = application.switches["sync-cursor-before-submit"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertFalse(isToggleOn(toggle))
        let help = application.staticTexts["sync-cursor-before-submit-help"]
        XCTAssertTrue(help.exists)
        XCTAssertEqual(help.label, "仅影响 TokChan 发起的提交和立即运行自动提交，不影响 Tokscale 定时自动提交。同步失败时不会提交。")
        toggle.click()
        XCTAssertTrue(waitUntil(timeout: 3) { self.isToggleOn(toggle) })
        XCTAssertFalse(application.buttons["apply-autosubmit-settings"].exists)
        application.toolbars.buttons["自动提交"].click()
        XCTAssertTrue(application.buttons["apply-autosubmit-settings"].waitForExistence(timeout: 3))
        application.toolbars.buttons["常规"].click()
        XCTAssertTrue(isToggleOn(toggle))
        application.windows.firstMatch.buttons[XCUIIdentifierCloseWindow].click()
        statusItem.rightClick()
        application.menuItems["设置…"].click()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(isToggleOn(toggle))
        toggle.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !self.isToggleOn(toggle) })
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

    private func isToggleOn(_ element: XCUIElement) -> Bool {
        if let number = element.value as? NSNumber { return number.boolValue }
        guard let value = element.value as? String else { return false }
        return value == "1" || value.caseInsensitiveCompare("on") == .orderedSame
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
