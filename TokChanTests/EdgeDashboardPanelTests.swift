import AppKit
import XCTest
@testable import TokChan

@MainActor
final class EdgeDashboardPanelTests: XCTestCase {
    private let screen = CGRect(x: -1600, y: 80, width: 1600, height: 1000)

    func testDropsNearTopAndBottomUseOnlyTheLeftOrRightSide() {
        for y in [screen.minY + 1, screen.maxY - 1] {
            for (x, side) in [(screen.midX - 1, EdgePanelPlacement.Side.left),
                              (screen.midX + 1, EdgePanelPlacement.Side.right)] {
                let placement = EdgePanelPlacement(dropPoint: CGPoint(x: x, y: y),
                    grabAnchor: CGPoint(x: 0.5, y: 0.5), screen: screen)
                XCTAssertEqual(placement.side, side)
                let full = placement.expandedFrame(in: screen)
                let tab = placement.frame(in: screen, reveal: 0)
                XCTAssertEqual(full.size, EdgePanelPlacement.contentSize)
                XCTAssertEqual(full, placement.frame(in: screen, reveal: 1))
                XCTAssertEqual(tab.width, 7)
                XCTAssertEqual(tab.minY, full.minY)
                XCTAssertEqual(tab.height, full.height)
                if side == .left {
                    XCTAssertEqual(tab.minX, screen.minX)
                    XCTAssertEqual(full.minX, screen.minX + 8)
                } else {
                    XCTAssertEqual(tab.maxX, screen.maxX)
                    XCTAssertEqual(full.maxX, screen.maxX - 8)
                }
                if y < screen.midY {
                    XCTAssertEqual(full.minY, screen.minY + 8)
                } else {
                    XCTAssertEqual(full.maxY, screen.maxY - 8)
                }
                for reveal in [0.2, 0.5, 0.8] {
                    let frame = placement.frame(in: screen, reveal: reveal)
                    XCTAssertTrue(screen.contains(frame))
                    XCTAssertEqual(frame.minY, full.minY)
                    XCTAssertEqual(frame.height, full.height)
                }
            }
        }
    }

    func testShortScreenFitsTheEntirePanelWithClearance() {
        let short = CGRect(x: 100, y: -900, width: 800, height: 550)
        let placement = EdgePanelPlacement(dropPoint: CGPoint(x: short.minX, y: short.maxY),
            grabAnchor: CGPoint(x: 0.5, y: 0.98), screen: short)
        let full = placement.expandedFrame(in: short)
        XCTAssertEqual(full.minY, short.minY + 8, accuracy: 0.001)
        XCTAssertEqual(full.maxY, short.maxY - 8, accuracy: 0.001)
        XCTAssertEqual(full.width / full.height, 380.0 / 708, accuracy: 0.001)
        XCTAssertEqual(placement.frame(in: short, reveal: 0).height, full.height, accuracy: 0.001)
    }

    func testDropKeepsGrabbedPointAtReleaseHeightOnEitherSide() {
        let display = CGRect(x: -1700, y: 120, width: 1600, height: 2000)
        for anchor in [CGPoint(x: 0.04, y: 0.97), CGPoint(x: 0.8, y: 0.99)] {
            for x in [display.minX + 1, display.maxX - 1] {
                let release = CGPoint(x: x, y: display.midY)
                let placement = EdgePanelPlacement(dropPoint: release, grabAnchor: anchor, screen: display)
                let full = placement.expandedFrame(in: display)
                XCTAssertEqual(full.minY + full.height * anchor.y, release.y, accuracy: 0.001)
                XCTAssertTrue(display.contains(full))
            }
        }
    }

    func testRepeatedExpansionAndModeSwitchNotifyDashboardOncePerPresentation() throws {
        guard NSScreen.main != nil else { throw XCTSkip("Requires a window server") }
        let model = DashboardViewModel(api: PreviewAPIService(), cli: PreviewCLIService(),
            preferencesStore: PreviewPreferencesStore(), npxLocator: PreviewNpxLocator(), cacheStore: PreviewCacheStore())
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let panel = EdgeDashboardPanel(viewModel: model)
        panel.expand()
        panel.enable()
        let window = try XCTUnwrap(NSApp.windows.compactMap { $0 as? NSPanel }.first {
            $0.isVisible && $0.title == "TokChan 贴边浮窗" && !previousWindows.contains(ObjectIdentifier($0))
        })
        XCTAssertEqual(window.accessibilitySubrole(), .floatingWindow)
        XCTAssertTrue(window.becomesKeyOnlyIfNeeded)
        let viewport = try XCTUnwrap(window.contentView)
        let body = try XCTUnwrap(viewport.subviews.compactMap { $0 as? NSVisualEffectView }.first)
        XCTAssertEqual(body.material, .popover)
        XCTAssertEqual(body.blendingMode, .behindWindow)
        XCTAssertEqual(body.state, .active)
        XCTAssertFalse(window.isOpaque)
        XCTAssertFalse(body.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(body.frame.intersection(viewport.bounds), viewport.bounds)
        XCTAssertGreaterThan(body.layer?.cornerRadius ?? 0, 0)
        XCTAssertEqual(viewport.accessibilityIdentifier(), "edge-panel-handle")
        XCTAssertTrue(viewport.accessibilityChildren()?.isEmpty == true)
        XCTAssertEqual(model.panelAppearanceCount, 0)
        panel.expand()
        panel.expand()
        XCTAssertEqual(model.panelAppearanceCount, 1)
        panel.disable()
        panel.disable()
        XCTAssertEqual(model.panelDisappearanceCount, 1)
        panel.enable()
        XCTAssertEqual(model.panelAppearanceCount, 1)
        panel.expand()
        panel.disable()
        XCTAssertEqual(model.panelAppearanceCount, 2)
        XCTAssertEqual(model.panelDisappearanceCount, 2)
    }

    func testStatusItemClickFollowsTheSelectedPresentationMode() async throws {
        guard NSScreen.main != nil else { throw XCTSkip("Requires a window server") }
        let model = DashboardViewModel(api: PreviewAPIService(), cli: PreviewCLIService(),
            preferencesStore: PreviewPreferencesStore(), npxLocator: PreviewNpxLocator(), cacheStore: PreviewCacheStore())
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let coordinator = NSStatusItemCoordinator(viewModel: model, settingsAction: .live,
            appUpdater: AppUpdater.offlineTest(), terminate: {})
        var settings = model.preferences
        settings.presentationMode = .edge
        model.updatePreferences(settings)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let edgeWindow = try XCTUnwrap(NSApp.windows.first {
            $0.title == "TokChan 贴边浮窗" && $0.isVisible && !previousWindows.contains(ObjectIdentifier($0))
        })
        coordinator.handleStatusButtonAction(.toggleDashboard)
        coordinator.handleStatusButtonAction(.toggleDashboard)
        XCTAssertEqual(model.panelAppearanceCount, 1)
        settings.presentationMode = .menuBar
        model.updatePreferences(settings)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertFalse(edgeWindow.isVisible)
        XCTAssertEqual(model.panelDisappearanceCount, 1)
    }

    func testSavedLiquidGlassAndLiveMaterialSwitchPreservePinnedDashboard() async throws {
        guard NSScreen.main != nil else { throw XCTSkip("Requires a window server") }
        let suite = "EdgeDashboardPanelTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        var preferences = store.load()
        preferences.presentationMode = .edge
        preferences.edgeLiquidGlassEnabled = true
        store.save(preferences)

        let model = DashboardViewModel(api: PreviewAPIService(), cli: PreviewCLIService(),
            preferencesStore: store, npxLocator: PreviewNpxLocator(), cacheStore: PreviewCacheStore())
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let coordinator = NSStatusItemCoordinator(viewModel: model, settingsAction: .live,
            appUpdater: AppUpdater.offlineTest(), terminate: {})
        defer { withExtendedLifetime(coordinator) {} }
        func deliverPreferences() async {
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        await deliverPreferences()
        let window = try XCTUnwrap(NSApp.windows.first {
            $0.title == "TokChan 贴边浮窗" && $0.isVisible && !previousWindows.contains(ObjectIdentifier($0))
        })
        defer { window.orderOut(nil) }
        let viewport = try XCTUnwrap(window.contentView)
        guard #available(macOS 26.0, *) else {
            XCTAssertNotNil(viewport.subviews.compactMap { $0 as? NSVisualEffectView }.first)
            return
        }

        XCTAssertFalse(viewport.subviews.contains { $0 is NSVisualEffectView })
        let content = try XCTUnwrap(viewport.subviews.first { view in view.subviews.contains { $0 is NSButton } })
        XCTAssertEqual(content.layer?.masksToBounds, true)
        XCTAssertEqual(content.layer?.cornerCurve, .continuous)
        XCTAssertEqual(content.layer?.cornerRadius, 16)
        let pin = try XCTUnwrap(content.subviews.compactMap { $0 as? NSButton }.first)
        let grip = try XCTUnwrap(content.subviews.first { $0.toolTip == "拖动调整吸附位置" })
        let startSize = window.frame.size
        coordinator.handleStatusButtonAction(.toggleDashboard)
        try await Task.sleep(for: .milliseconds(350))
        pin.performClick(nil)
        let expanded = window.frame
        XCTAssertGreaterThan(expanded.width, startSize.width)

        preferences.edgeLiquidGlassEnabled = false
        model.updatePreferences(preferences)
        await deliverPreferences()
        let frosted = try XCTUnwrap(viewport.subviews.compactMap { $0 as? NSVisualEffectView }.first)
        XCTAssertTrue(content.superview === viewport)
        XCTAssertEqual(frosted.frame, content.frame)
        XCTAssertEqual(content.layer?.cornerRadius, frosted.layer?.cornerRadius)
        XCTAssertEqual(frosted.material, .popover)
        XCTAssertEqual(pin.accessibilityLabel(), "解除固定")
        XCTAssertEqual(window.frame, expanded)

        preferences.edgeLiquidGlassEnabled = true
        model.updatePreferences(preferences)
        await deliverPreferences()
        XCTAssertNil(frosted.superview)
        XCTAssertEqual(content.layer?.cornerRadius, 16)
        XCTAssertFalse(viewport.subviews.contains { $0 is NSVisualEffectView })
        XCTAssertTrue(content.superview === viewport)
        XCTAssertTrue(pin.superview === content)
        XCTAssertTrue(grip.superview === content)
        XCTAssertEqual(pin.accessibilityLabel(), "解除固定")
        XCTAssertEqual(window.frame, expanded)
        XCTAssertEqual(model.panelAppearanceCount, 1)
        XCTAssertEqual(model.panelDisappearanceCount, 0)

        let didReset = await model.resetConfiguration(disableLaunchAtLogin: {})
        XCTAssertTrue(didReset)
        await deliverPreferences()
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(store.load().edgeLiquidGlassEnabled)
        XCTAssertEqual(model.panelDisappearanceCount, 1)
        var restored = model.preferences
        restored.presentationMode = .edge
        model.updatePreferences(restored)
        await deliverPreferences()
        XCTAssertTrue(window.isVisible)
        XCTAssertNotNil(viewport.subviews.compactMap { $0 as? NSVisualEffectView }.first)
        XCTAssertEqual(window.frame.size, startSize)
    }

    func testGlassHoverPreservesKeyWindowAndExplicitActionsTakeFocus() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Requires Liquid Glass") }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        try XCTSkipIf(session?["CGSSessionScreenIsLocked"] as? Bool == true, "Requires an unlocked desktop")
        let screen = try XCTUnwrap(NSScreen.main)
        let store = PreviewPreferencesStore()
        var preferences = store.load()
        preferences.edgeLiquidGlassEnabled = true
        store.save(preferences)
        let model = DashboardViewModel(api: PreviewAPIService(), cli: PreviewCLIService(),
            preferencesStore: store, npxLocator: PreviewNpxLocator(), cacheStore: PreviewCacheStore())
        let other = NSPanel(contentRect: CGRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY,
            width: 100, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
        NSApp.activate(ignoringOtherApps: true)
        other.makeKeyAndOrderFront(nil)
        defer { other.orderOut(nil) }
        var pointer = CGPoint.zero
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let panel = EdgeDashboardPanel(viewModel: model, mouseLocation: { pointer })
        panel.enable()
        defer { panel.disable() }
        let window = try XCTUnwrap(NSApp.windows.first {
            $0.title == "TokChan 贴边浮窗" && !previousWindows.contains(ObjectIdentifier($0))
        })
        let viewport = try XCTUnwrap(window.contentView)
        pointer = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let enter = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil))
        viewport.mouseEntered(with: enter)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(other.isKeyWindow)
        XCTAssertFalse(window.isKeyWindow)

        // Click the grip, which can receive a click without requesting keyboard input.
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let click = try XCTUnwrap(NSEvent.mouseEvent(with: type,
                location: CGPoint(x: 16, y: window.frame.height - 12), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(click)
        }
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertTrue(NSApp.isActive)
        other.makeKeyAndOrderFront(nil)
        XCTAssertFalse(window.isKeyWindow)
        panel.expand()
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertEqual(model.panelAppearanceCount, 1)
    }

    func testTrackingPinAndDragOnNativePanel() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let model = DashboardViewModel(api: PreviewAPIService(), cli: PreviewCLIService(),
            preferencesStore: PreviewPreferencesStore(), npxLocator: PreviewNpxLocator(), cacheStore: PreviewCacheStore())
        var pointer = CGPoint.zero
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let panel = EdgeDashboardPanel(viewModel: model, mouseLocation: { pointer })
        panel.enable()
        defer { panel.disable() }
        let window = try XCTUnwrap(NSApp.windows.first {
            $0.title == "TokChan 贴边浮窗" && $0.isVisible && !previousWindows.contains(ObjectIdentifier($0))
        })
        let viewport = try XCTUnwrap(window.contentView)
        let area = try XCTUnwrap(viewport.trackingAreas.first { $0.owner === viewport })
        XCTAssertTrue(area.options.contains(.activeAlways))
        let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        pointer = CGPoint(x: window.frame.midX, y: window.frame.midY)
        viewport.mouseEntered(with: event)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.panelAppearanceCount, 1)
        XCTAssertEqual(window.frame.maxX, screen.visibleFrame.maxX - 8, accuracy: 1)
        // The panel slid away from the original handle. AppKit reports an exit although the
        // pointer is stationary in the narrow gap between the panel and the display edge.
        viewport.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(model.panelDisappearanceCount, 0)
        pointer = CGPoint(x: window.frame.midX, y: window.frame.midY)
        viewport.mouseEntered(with: event)
        XCTAssertEqual(model.panelAppearanceCount, 1)
        let body = try XCTUnwrap(viewport.subviews.first { view in view.subviews.contains { $0 is NSButton } })
        let pin = try XCTUnwrap(body.subviews.compactMap { $0 as? NSButton }.first)
        pin.performClick(nil)
        pointer = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        viewport.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(model.panelDisappearanceCount, 0)

        let grip = try XCTUnwrap(body.subviews.first { $0.toolTip == "拖动调整吸附位置" })
        func dragEvent(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let start = window.convertPoint(toScreen: grip.convert(CGPoint(x: 16, y: 14), to: nil))
        let initialFrame = window.frame
        let grabY = start.y - initialFrame.minY
        let desiredOriginY = screen.visibleFrame.minY + 8 + (screen.visibleFrame.height - 16 - initialFrame.height) * 0.3
        let end = CGPoint(x: screen.visibleFrame.minX + 2, y: desiredOriginY + grabY)
        grip.mouseDown(with: try dragEvent(.leftMouseDown, at: start))
        let firstMove = CGPoint(x: start.x - 30, y: start.y - 16)
        grip.mouseDragged(with: try dragEvent(.leftMouseDragged, at: firstMove))
        XCTAssertEqual(window.frame.minX, initialFrame.minX - 30, accuracy: 1)
        XCTAssertEqual(window.frame.minY, initialFrame.minY - 16, accuracy: 1)
        grip.mouseDragged(with: try dragEvent(.leftMouseDragged, at: end))
        grip.mouseUp(with: try dragEvent(.leftMouseUp, at: end))
        XCTAssertEqual(window.frame.minX, screen.visibleFrame.minX + 8, accuracy: 1)
        XCTAssertEqual(window.frame.minY + grabY, end.y, accuracy: 1)
        window.makeKeyAndOrderFront(nil)
        XCTAssertEqual(window.animationBehavior, .none)
        pin.performClick(nil)
        var sawIntermediateFrame = false
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        while window.frame.width > 7 && ProcessInfo.processInfo.systemUptime < deadline {
            let frame = window.frame
            if frame.width < initialFrame.width - 1 {
                sawIntermediateFrame = true
                XCTAssertEqual(frame.minX, screen.visibleFrame.minX, accuracy: 1)
                XCTAssertEqual(frame.minY, end.y - grabY, accuracy: 1)
                XCTAssertEqual(frame.height, initialFrame.height, accuracy: 1)
                XCTAssertTrue(window.isVisible)
                XCTAssertTrue(window.isKeyWindow)
            }
            try await Task.sleep(for: .milliseconds(12))
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertTrue(sawIntermediateFrame)
        }
        XCTAssertEqual(model.panelDisappearanceCount, 1)
        XCTAssertEqual(window.frame.width, 7, accuracy: 1)
        XCTAssertEqual(window.frame.minY + grabY, end.y, accuracy: 1)
        XCTAssertEqual(window.frame.height, initialFrame.height, accuracy: 1)
        var preferences = model.preferences
        preferences.edgePeekWidth = 23
        model.updatePreferences(preferences)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertEqual(window.frame.width, 23, accuracy: 1)
        XCTAssertEqual(window.frame.minX, screen.visibleFrame.minX, accuracy: 1)
    }
}
