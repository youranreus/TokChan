import AppKit
import XCTest
@testable import TokChan

@MainActor
final class StatusItemPresentationTests: XCTestCase {
    func testRoutesOnlyLeftAndRightMouseUp() {
        XCTAssertEqual(StatusItemClickAction.action(for: .leftMouseUp), .toggleDashboard)
        XCTAssertEqual(StatusItemClickAction.action(for: .rightMouseUp), .showStatusMenu)
        XCTAssertEqual(StatusItemClickAction.action(for: .mouseMoved), .ignore)
    }

    func testMenuDescriptorsAreDynamicAndOrdered() {
        XCTAssertEqual(
            StatusMenuBuilder.descriptors(
                freshness: "数据日期 2026-09-05 · 更新于 1 小时前",
                diagnostics: ["统计读取：离线", "本地保存：只读"]
            ),
            [
                .information("数据日期 2026-09-05 · 更新于 1 小时前"),
                .diagnostics(["统计读取：离线", "本地保存：只读"]),
                .separator,
                .settings,
                .quit
            ]
        )
        XCTAssertEqual(
            StatusMenuBuilder.descriptors(freshness: nil, diagnostics: []),
            [.settings, .quit]
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
