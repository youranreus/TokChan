import AppKit
import XCTest
@testable import TokChan

@MainActor
final class StatusItemPresentationTests: XCTestCase {
    func testCursorConnectionPresentationExposesOnlyTheSafeActionForEachState() {
        XCTAssertFalse(CursorConnectionState.idle.showsLoginAction)
        XCTAssertFalse(CursorConnectionState.checking.showsLoginAction)
        XCTAssertFalse(CursorConnectionState.loggedIn.showsLoginAction)
        XCTAssertTrue(CursorConnectionState.needsLogin.showsLoginAction)
        XCTAssertFalse(CursorConnectionState.checkFailed("offline").showsLoginAction)

        XCTAssertFalse(CursorConnectionState.needsLogin.showsRetryAction)
        XCTAssertTrue(CursorConnectionState.checkFailed("offline").showsRetryAction)
    }

    func testRoutesOnlyLeftAndRightMouseUp() {
        XCTAssertEqual(StatusItemClickAction.action(for: .leftMouseUp), .toggleDashboard)
        XCTAssertEqual(StatusItemClickAction.action(for: .rightMouseUp), .showStatusMenu)
        XCTAssertEqual(StatusItemClickAction.action(for: .mouseMoved), .ignore)
    }

    func testDashboardPopoverActionActivatesShowsAndMakesPopoverKeyInOrder() {
        var events: [String] = []
        let action = DashboardPopoverAction(
            isShown: false,
            activate: { events.append("activate") },
            close: { events.append("close") },
            show: { events.append("show") },
            makeKey: { events.append("makeKey") }
        )

        action.perform()

        XCTAssertEqual(events, ["activate", "show", "makeKey"])
    }

    func testDashboardPopoverActionClosesWithoutActivating() {
        var events: [String] = []
        let action = DashboardPopoverAction(
            isShown: true,
            activate: { events.append("activate") },
            close: { events.append("close") },
            show: { events.append("show") },
            makeKey: { events.append("makeKey") }
        )

        action.perform()

        XCTAssertEqual(events, ["close"])
    }

    func testMenuDescriptorsAreDynamicAndOrdered() {
        XCTAssertEqual(
            StatusMenuBuilder.descriptors(
                freshness: "数据日期 2026-09-05 · 统计读取于 1 小时前",
                diagnostics: ["统计读取：离线", "本地保存：只读"],
                actionsEnabled: true
            ),
            [
                .information("数据日期 2026-09-05 · 统计读取于 1 小时前"),
                .diagnostics(["统计读取：离线", "本地保存：只读"]),
                .separator,
                .submitAndRefresh(isEnabled: true),
                .refreshStatistics(isEnabled: true),
                .separator,
                .settings,
                .quit
            ]
        )
        XCTAssertEqual(
            StatusMenuBuilder.descriptors(
                freshness: nil,
                diagnostics: [],
                actionsEnabled: false
            ),
            [
                .submitAndRefresh(isEnabled: false),
                .refreshStatistics(isEnabled: false),
                .separator,
                .settings,
                .quit
            ]
        )
    }

    func testMenuActionTitlesDistinguishUploadFromReadOnlyRefresh() {
        XCTAssertEqual(StatusMenuBuilder.title(for: .submitAndRefresh(isEnabled: true)), "提交并拉取")
        XCTAssertEqual(StatusMenuBuilder.title(for: .refreshStatistics(isEnabled: true)), "拉取远程数据")
    }

    func testStatusItemPresentationSwitchesBetweenIconOnlyAndReadableTitle() {
        let iconOnly = StatusItemPresentation(statusTitle: nil)
        XCTAssertEqual(iconOnly.title, "")
        XCTAssertEqual(iconOnly.accessibilityLabel, "TokChan")
        XCTAssertFalse(iconOnly.usesVariableLength)

        let titled = StatusItemPresentation(statusTitle: "1K · $12.50")
        XCTAssertEqual(titled.title, "1K · $12.50")
        XCTAssertEqual(titled.accessibilityLabel, "TokChan，1K · $12.50")
        XCTAssertTrue(titled.usesVariableLength)

        let button = NSButton(title: titled.title, target: nil, action: nil)
        let nativeTitle = button.attributedTitle
        let nativeFont = nativeTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let nativeColor = nativeTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let adjustedTitle = titled.baselineAdjustedTitle(from: nativeTitle)
        XCTAssertEqual(adjustedTitle.string, titled.title)
        XCTAssertEqual(
            (adjustedTitle.attribute(.baselineOffset, at: 0, effectiveRange: nil) as? NSNumber)?.doubleValue,
            -1
        )
        XCTAssertEqual(
            adjustedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
            nativeFont
        )
        XCTAssertEqual(
            adjustedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            nativeColor
        )
    }

    func testSettingsActionPrefersSwiftUISettingsCommand() {
        var activations = 0
        var commandInvocations = 0
        var selectors: [String] = []
        let action = SettingsWindowAction(
            activate: { activations += 1 },
            invokeSettingsCommand: {
                commandInvocations += 1
                return true
            },
            send: { selector in
                selectors.append(NSStringFromSelector(selector))
                return true
            }
        )

        action.perform()

        XCTAssertEqual(activations, 1)
        XCTAssertEqual(commandInvocations, 1)
        XCTAssertTrue(selectors.isEmpty)
    }

    func testSettingsActionStopsAfterPrimarySelectorSucceeds() {
        var activations = 0
        var selectors: [String] = []
        let action = SettingsWindowAction(
            activate: { activations += 1 },
            send: { selector in
                selectors.append(NSStringFromSelector(selector))
                return true
            }
        )

        action.perform()

        XCTAssertEqual(activations, 1)
        XCTAssertEqual(selectors, ["showSettingsWindow:"])
    }

    func testSettingsActionUsesLegacyFallbackOnlyWhenNeeded() {
        var activations = 0
        var selectors: [String] = []
        let action = SettingsWindowAction(
            activate: { activations += 1 },
            send: { selector in
                selectors.append(NSStringFromSelector(selector))
                return false
            }
        )

        action.perform()

        XCTAssertEqual(activations, 1)
        XCTAssertEqual(selectors, ["showSettingsWindow:", "showPreferencesWindow:"])
    }
}
