import AppKit
import Combine
import SwiftUI

@MainActor
final class EdgeDashboardPanel: NSObject {
    private let viewModel: DashboardViewModel
    private let mouseLocation: () -> CGPoint
    private let window: EdgeWindow
    private var previousApplication: NSRunningApplication?
    private let viewport = EdgePanelViewport()
    private let body = NSView(frame: CGRect(origin: .zero, size: EdgePanelPlacement.contentSize))
    private var frost: NSVisualEffectView?
    private var materialSubscription: AnyCancellable?
    private var widthSubscription: AnyCancellable?
    private let pin = NSButton()
    private var screenID: NSNumber?
    private var placement = EdgePanelPlacement()
    private var isEnabled = false
    private var isExpanded = false
    private var isPinned = false
    private var dragAnchor: CGPoint?
    private var reveal: CGFloat = 0
    private var motion: Task<Void, Never>?
    private var dismissal: Task<Void, Never>?
    private var menuGraceUntil: TimeInterval = 0

    init(viewModel: DashboardViewModel, mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation }) {
        self.mouseLocation = mouseLocation
        self.viewModel = viewModel
        window = EdgeWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        super.init()
        window.title = "TokChan 贴边浮窗"
        window.setAccessibilitySubrole(.floatingWindow)
        // Sliding is driven by layout; an order-out animation would also shrink a key panel.
        window.animationBehavior = .none
        window.level = .floating
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = viewport
        viewport.wantsLayer = true
        viewport.layer?.masksToBounds = true
        window.onPrimaryClick = { [weak self] in self?.focusGlassDashboard() }
        viewport.onEnter = { [weak self] in self?.pointerEntered() }
        viewport.onExit = { [weak self] in self?.scheduleDismissal() }
        viewport.onPress = { [weak self] in self?.expand() }

        // Clip the complete moving surface. The viewport only clips the slide at the screen edge.
        body.wantsLayer = true
        body.layer?.cornerCurve = .continuous
        body.layer?.masksToBounds = true
        configureBody()
        viewport.addSubview(body)
        updateFrost(glassEnabled: viewModel.preferences.edgeLiquidGlassEnabled)
        widthSubscription = viewModel.$preferences
            .map(\.edgePeekWidth)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, isEnabled, dragAnchor == nil else { return }
                layout()
            }
        materialSubscription = viewModel.$preferences
            .map(\.edgeLiquidGlassEnabled)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.updateFrost(glassEnabled: enabled)
            }
    }

    private func updateFrost(glassEnabled: Bool) {
        defer { window.invalidateShadow() }
        if #available(macOS 26.0, *), glassEnabled {
            body.layer?.cornerRadius = EdgeDashboardContent.glassRadius
            frost?.removeFromSuperview()
            frost = nil
            return
        }
        let frostRadius: CGFloat = 10
        body.layer?.cornerRadius = frostRadius
        guard frost == nil else { return }
        let frosted = NSVisualEffectView(frame: body.frame)
        frosted.material = .popover
        frosted.blendingMode = .behindWindow
        frosted.state = .active
        frosted.wantsLayer = true
        frosted.layer?.cornerRadius = frostRadius
        frosted.layer?.cornerCurve = .continuous
        frosted.layer?.masksToBounds = true
        viewport.addSubview(frosted, positioned: .below, relativeTo: body)
        frost = frosted
    }

    private func configureBody() {
        let hosting = NSHostingView(rootView: EdgeDashboardContent(viewModel: viewModel)
            .environment(\.locale, Locale(identifier: "zh_CN")))
        hosting.sizingOptions = []
        hosting.frame = body.bounds
        body.addSubview(hosting)
        let grip = EdgePanelGrip(frame: CGRect(x: 0, y: 680, width: 344, height: 28))
        grip.toolTip = "拖动调整吸附位置"
        let line = NSBox(frame: CGRect(x: 168, y: 12, width: 44, height: 4))
        line.boxType = .custom
        line.borderWidth = 0
        line.cornerRadius = 2
        line.fillColor = .tertiaryLabelColor
        grip.addSubview(line)
        grip.begin = { [weak self] anchor in self?.beginDrag(at: anchor) }
        grip.move = { [weak self] point in self?.moveDrag(to: point) }
        grip.end = { [weak self] point in self?.finishDrag(at: point) }
        body.addSubview(grip)
        pin.frame = CGRect(x: 344, y: 680, width: 32, height: 28)
        pin.isBordered = false
        pin.target = self
        pin.action = #selector(togglePin)
        pin.setAccessibilityIdentifier("edge-panel-pin")
        updatePin()
        body.addSubview(pin)
    }

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        screenChanged()
    }

    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        menuGraceUntil = 0
        motion?.cancel()
        dismissal?.cancel()
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        returnFocusIfNeeded()
        window.orderOut(nil)
        if isExpanded { viewModel.panelDidDisappear() }
        isExpanded = false
        isPinned = false
        dragAnchor = nil
        reveal = 0
        updatePin()
    }

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.deviceDescription[.init("NSScreenNumber")] as? NSNumber == screenID } ?? NSScreen.main
    }

    @objc private func screenChanged() {
        guard isEnabled, let screen else { return }
        screenID = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber
        dragAnchor = nil
        layout()
        window.orderFrontRegardless()
    }

    func expand() {
        guard isEnabled else { return }
        showDashboard()
        focusGlassDashboard()
        // The pointer starts on the menu bar and needs time to travel to the panel.
        menuGraceUntil = ProcessInfo.processInfo.systemUptime + 1.5
        scheduleDismissal()
    }

    private func focusGlassDashboard() {
        guard #available(macOS 26.0, *), isExpanded, viewModel.preferences.edgeLiquidGlassEnabled,
              !window.isKeyWindow || !NSApp.isActive else { return }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = front
        } else {
            previousApplication = nil
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func returnFocusIfNeeded() {
        defer { previousApplication = nil }
        guard window.isKeyWindow, NSApp.isActive, let previousApplication,
              !previousApplication.isTerminated else { return }
        previousApplication.activate(options: [])
    }

    private func pointerEntered() {
        guard isEnabled, window.frame.contains(mouseLocation()) else { return }
        menuGraceUntil = 0
        dismissal?.cancel()
        showDashboard()
    }

    private func showDashboard() {
        guard !isExpanded else { return }
        isExpanded = true
        viewModel.panelWillAppear()
        animate(to: 1)
        viewModel.panelDidAppear()
    }

    private func scheduleDismissal() {
        dismissal?.cancel()
        guard isExpanded, !isPinned, dragAnchor == nil else { return }
        let delay = max(0.22, menuGraceUntil - ProcessInfo.processInfo.systemUptime)
        dismissal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, isEnabled, isExpanded, !isPinned,
                  dragAnchor == nil else { return }
            let point = mouseLocation()
            guard !window.frame.contains(point) else { return }
            if let screen, placement.hoverCorridor(in: screen.visibleFrame).contains(point) {
                // The gap is outside the window, so the next pointer move may produce no exit event.
                scheduleDismissal()
                return
            }
            isExpanded = false
            viewModel.panelDidDisappear()
            animate(to: 0)
        }
    }

    @objc private func togglePin() {
        isPinned.toggle()
        updatePin()
        scheduleDismissal()
    }

    private func updatePin() {
        let label = isPinned ? "解除固定" : "固定展开"
        pin.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: label)
        pin.toolTip = label
        pin.setAccessibilityLabel(label)
    }

    private func beginDrag(at anchor: CGPoint) {
        dismissal?.cancel()
        motion?.cancel()
        reveal = 1
        layout()
        dragAnchor = anchor
    }

    private func moveDrag(to point: CGPoint) {
        guard let dragAnchor else { return }
        let size = window.frame.size
        window.setFrameOrigin(CGPoint(x: point.x - dragAnchor.x * size.width,
                                      y: point.y - dragAnchor.y * size.height))
    }

    private func finishDrag(at point: CGPoint) {
        guard let anchor = dragAnchor else { return }
        dragAnchor = nil
        if let target = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? screen {
            screenID = target.deviceDescription[.init("NSScreenNumber")] as? NSNumber
            placement = EdgePanelPlacement(dropPoint: point, grabAnchor: anchor, screen: target.visibleFrame)
        }
        layout()
        scheduleDismissal()
    }

    private func animate(to target: CGFloat) {
        motion?.cancel()
        let start = reveal
        let opening = target > start
        let duration = (opening ? 0.26 : 0.22) * abs(target - start)
        guard duration > 0, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            reveal = target
            layout()
            return
        }
        let began = ProcessInfo.processInfo.systemUptime
        motion = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let t = min(1, (ProcessInfo.processInfo.systemUptime - began) / duration)
                // Cubic Bézier with evenly spaced time controls. Open promptly, then settle;
                // closing starts more gently and comes to rest at the visible edge.
                let u = 1 - t
                let first: CGFloat = opening ? 0.72 : 0.08
                let second: CGFloat = opening ? 1 : 0.94
                let eased = 3 * u * u * t * first + 3 * u * t * t * second + t * t * t
                reveal = start + (target - start) * eased
                layout()
                if t == 1 { return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func layout() {
        guard let area = screen?.visibleFrame else { return }
        let frame = placement.frame(in: area, reveal: reveal, peekWidth: viewModel.preferences.edgePeekWidth)
        let full = placement.expandedFrame(in: area)
        window.setFrame(frame, display: false)
        let origin = placement.contentOrigin(window: frame, full: full)
        body.frame = CGRect(origin: origin, size: full.size)
        body.bounds = CGRect(origin: .zero, size: EdgePanelPlacement.contentSize)
        frost?.frame = body.frame
        viewport.showsDashboard = isExpanded
        window.hasShadow = reveal > 0
        if reveal == 1 { window.invalidateShadow() }
        // Return keyboard focus only after the moving panel has reached its narrow strip.
        if reveal == 0, !isExpanded, window.isKeyWindow {
            returnFocusIfNeeded()
            window.makeFirstResponder(nil)
            window.orderOut(nil)
            window.orderFrontRegardless()
        }
    }
}

/// The grip and pin sit above the top 28 points of the same glass surface.
private struct EdgeDashboardContent: View {
    static let glassRadius: CGFloat = 16
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let content = DashboardView(viewModel: viewModel).padding(.top, 28)
        if #available(macOS 26.0, *) {
            let enabled = viewModel.preferences.edgeLiquidGlassEnabled
            let shape = RoundedRectangle(cornerRadius: Self.glassRadius)
            content
                .background {
                    if enabled && reduceTransparency {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                    }
                }
                .glassEffect(enabled && !reduceTransparency ? .regular : .identity, in: shape)
                .overlay {
                    if enabled && contrast == .increased {
                        shape.strokeBorder(Color.primary.opacity(0.42)).allowsHitTesting(false)
                    }
                }
        } else {
            content
        }
    }
}

private final class EdgeWindow: NSPanel {
    var onPrimaryClick: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { onPrimaryClick?() }
        super.sendEvent(event)
    }
}

private final class EdgePanelViewport: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onPress: (() -> Void)?
    var showsDashboard = false {
        didSet {
            if showsDashboard != oldValue { updateAccessibility() }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        updateAccessibility()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }

    private func updateAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(showsDashboard ? .group : .button)
        setAccessibilityLabel(showsDashboard ? "贴边浮窗" : "展开贴边浮窗")
        setAccessibilityIdentifier(showsDashboard ? "edge-panel-content" : "edge-panel-handle")
    }

    override func accessibilityChildren() -> [Any]? {
        showsDashboard ? super.accessibilityChildren() : []
    }

    override func accessibilityPerformPress() -> Bool {
        guard !showsDashboard else { return super.accessibilityPerformPress() }
        onPress?()
        return true
    }
}

private final class EdgePanelGrip: NSView {
    var begin: ((CGPoint) -> Void)?
    var move: ((CGPoint) -> Void)?
    var end: ((CGPoint) -> Void)?
    private var pressAnchor: CGPoint?
    private var isDragging = false

    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDragged(with event: NSEvent) {
        guard let point = window?.convertPoint(toScreen: event.locationInWindow) else { return }
        if !isDragging {
            guard let pressAnchor else { return }
            isDragging = true
            begin?(pressAnchor)
        }
        move?(point)
    }
    override func mouseDown(with event: NSEvent) {
        guard let body = superview else { return }
        let local = body.convert(event.locationInWindow, from: nil)
        pressAnchor = CGPoint(x: local.x / body.bounds.width, y: local.y / body.bounds.height)
        isDragging = false
    }
    override func mouseUp(with event: NSEvent) {
        if isDragging, let window { end?(window.convertPoint(toScreen: event.locationInWindow)) }
        pressAnchor = nil
        isDragging = false
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}
