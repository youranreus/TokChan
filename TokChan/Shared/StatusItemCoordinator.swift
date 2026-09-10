import AppKit
import Combine
import SwiftUI

enum StatusItemClickAction: Equatable {
    case toggleDashboard
    case showStatusMenu
    case ignore

    static func action(for eventType: NSEvent.EventType) -> Self {
        switch eventType {
        case .leftMouseUp: return .toggleDashboard
        case .rightMouseUp: return .showStatusMenu
        default: return .ignore
        }
    }
}

enum StatusMenuDescriptor: Equatable {
    case information(String)
    case diagnostics([String])
    case separator
    case submitAndRefresh(isEnabled: Bool)
    case refreshStatistics(isEnabled: Bool)
    case dataMode(DashboardDataMode, isSelected: Bool, isEnabled: Bool)
    case checkForUpdates(isEnabled: Bool)
    case settings
    case quit
}

enum StatusMenuBuilder {
    static func descriptors(
        freshness: String?,
        diagnostics: [String],
        actionsEnabled: Bool,
        applicationInfo: String? = nil,
        selectedMode: DashboardDataMode? = nil,
        canCheckForUpdates: Bool = false
    ) -> [StatusMenuDescriptor] {
        var items: [StatusMenuDescriptor] = []
        if let applicationInfo { items.append(.information(applicationInfo)) }
        if let freshness { items.append(.information(freshness)) }
        if !diagnostics.isEmpty { items.append(.diagnostics(diagnostics)) }
        if !items.isEmpty { items.append(.separator) }
        items.append(.submitAndRefresh(isEnabled: actionsEnabled))
        items.append(.refreshStatistics(isEnabled: actionsEnabled))
        if let selectedMode {
            items.append(.separator)
            items.append(.dataMode(.local, isSelected: selectedMode == .local, isEnabled: actionsEnabled))
            items.append(.dataMode(.online, isSelected: selectedMode == .online, isEnabled: actionsEnabled))
        }
        items.append(.separator)
        if applicationInfo != nil || selectedMode != nil {
            items.append(.checkForUpdates(isEnabled: canCheckForUpdates))
        }
        items.append(.settings)
        items.append(.quit)
        return items
    }

    /// Action titles are defined here only, so the dashboard button and the menu cannot drift.
    static func title(for descriptor: StatusMenuDescriptor) -> String? {
        switch descriptor {
        case .submitAndRefresh: return "提交并拉取"
        case .refreshStatistics: return "拉取远程数据"
        case let .dataMode(mode, _, _): return "\(mode.title)模式"
        case .checkForUpdates: return "检查更新…"
        case .information, .diagnostics, .separator, .settings, .quit: return nil
        }
    }
}

struct StatusItemPresentation: Equatable {
    let title: String
    let accessibilityLabel: String
    let usesVariableLength: Bool

    init(statusTitle: String?) {
        if let statusTitle, !statusTitle.isEmpty {
            title = statusTitle
            accessibilityLabel = "TokChan，\(statusTitle)"
            usesVariableLength = true
        } else {
            title = ""
            accessibilityLabel = "TokChan"
            usesVariableLength = false
        }
    }

    func baselineAdjustedTitle(from nativeTitle: NSAttributedString) -> NSAttributedString {
        guard usesVariableLength, nativeTitle.length > 0 else { return nativeTitle }
        let adjustedTitle = NSMutableAttributedString(attributedString: nativeTitle)
        adjustedTitle.addAttribute(
            .baselineOffset,
            value: -1,
            range: NSRange(location: 0, length: adjustedTitle.length)
        )
        return adjustedTitle
    }
}

@MainActor
struct DashboardPopoverAction {
    let isShown: Bool
    private let activate: () -> Void
    private let close: () -> Void
    private let show: () -> Void
    private let makeKey: () -> Void

    init(
        isShown: Bool,
        activate: @escaping () -> Void,
        close: @escaping () -> Void,
        show: @escaping () -> Void,
        makeKey: @escaping () -> Void
    ) {
        self.isShown = isShown
        self.activate = activate
        self.close = close
        self.show = show
        self.makeKey = makeKey
    }

    func perform() {
        if isShown {
            close()
        } else {
            activate()
            show()
            makeKey()
        }
    }
}

@MainActor
struct SettingsWindowAction {
    private let activate: () -> Void
    private let invokeSettingsCommand: () -> Bool
    private let send: (Selector) -> Bool
    init(
        activate: @escaping () -> Void,
        invokeSettingsCommand: @escaping () -> Bool = { false },
        send: @escaping (Selector) -> Bool
    ) {
        self.activate = activate
        self.invokeSettingsCommand = invokeSettingsCommand
        self.send = send
    }

    func perform() {
        activate()
        if invokeSettingsCommand() { return }
        if !send(Selector(("showSettingsWindow:"))) {
            _ = send(Selector(("showPreferencesWindow:")))
        }
    }

    static var live: Self {
        Self(
            activate: { NSApplication.shared.activate(ignoringOtherApps: true) },
            invokeSettingsCommand: {
                guard let event = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .command,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: 0,
                    context: nil,
                    characters: ",",
                    charactersIgnoringModifiers: ",",
                    isARepeat: false,
                    keyCode: 43
                ) else { return false }
                return NSApplication.shared.mainMenu?.performKeyEquivalent(with: event) ?? false
            },
            send: { selector in
                NSApplication.shared.sendAction(selector, to: nil, from: nil)
            }
        )
    }
}

@MainActor
final class NSStatusItemCoordinator: NSObject, NSPopoverDelegate, NSMenuDelegate {
    private let viewModel: DashboardViewModel
    private let settingsAction: SettingsWindowAction
    private let appUpdater: AppUpdating
    private let applicationInfo: @MainActor () -> String
    private let terminate: () -> Void
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let hostingController: NSHostingController<AnyView>
    private var transientStatusMenu: NSMenu?
    private var cancellables: Set<AnyCancellable> = []

    init(
        viewModel: DashboardViewModel,
        settingsAction: SettingsWindowAction,
        appUpdater: AppUpdating,
        applicationInfo: @escaping @MainActor () -> String = NSStatusItemCoordinator.bundleApplicationInfo,
        terminate: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.settingsAction = settingsAction
        self.appUpdater = appUpdater
        self.applicationInfo = applicationInfo
        self.terminate = terminate
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        hostingController = NSHostingController(rootView: AnyView(
            DashboardView(viewModel: viewModel)
                .environment(\.locale, Locale(identifier: "zh_CN"))
        ))
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 680)
        popover.contentViewController = hostingController
        popover.delegate = self

        if let button = statusItem.button {
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                button.image = image
            }
            button.toolTip = "TokChan"
            button.setAccessibilityLabel("TokChan")
            button.target = self
            button.action = #selector(statusButtonPressed(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // @Published emits the incoming value before the stored property is updated.
        viewModel.$preferences
            .sink { [weak self] preferences in
                guard let self else { return }
                self.updateStatusItem(
                    with: self.viewModel.statusItemTitle(for: preferences)
                )
            }
            .store(in: &cancellables)
        viewModel.$profileState
            .sink { [weak self] _ in self?.synchronizeStatusItem() }
            .store(in: &cancellables)
        synchronizeStatusItem()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func statusButtonPressed(_ sender: NSStatusBarButton) {
        guard let event = NSApplication.shared.currentEvent else { return }
        switch StatusItemClickAction.action(for: event.type) {
        case .toggleDashboard:
            DashboardPopoverAction(
                isShown: popover.isShown,
                activate: { NSApplication.shared.activate(ignoringOtherApps: true) },
                close: { [popover] in popover.performClose(sender) },
                show: { [popover] in
                    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
                },
                makeKey: { [popover] in
                    // `show` creates the popover window; key it so AppKit owns transient dismissal.
                    popover.contentViewController?.view.window?.makeKey()
                }
            ).perform()
        case .showStatusMenu:
            if popover.isShown { popover.performClose(sender) }
            presentStatusMenu(from: sender)
        case .ignore:
            break
        }
    }

    func popoverDidShow(_ notification: Notification) {
        viewModel.panelDidAppear()
    }

    func popoverDidClose(_ notification: Notification) {
        viewModel.panelDidDisappear()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === transientStatusMenu else { return }
        statusItem.menu = nil
        transientStatusMenu = nil
    }

    private func presentStatusMenu(from button: NSStatusBarButton) {
        let menu = makeMenu()
        menu.delegate = self
        transientStatusMenu = menu
        statusItem.menu = menu
        defer {
            if transientStatusMenu === menu {
                statusItem.menu = nil
                transientStatusMenu = nil
            }
        }
        button.performClick(nil)
    }

    private func makeMenu() -> NSMenu {
        let freshness = SnapshotFreshnessFormatter.text(
            fetchedAt: viewModel.cacheSavedAt,
            dataDate: viewModel.profileState.loadedValue?.dateRange?.end
        )
        let descriptors = StatusMenuBuilder.descriptors(
            freshness: freshness,
            diagnostics: viewModel.diagnosticMessages,
            actionsEnabled: !viewModel.isPerformingOperation,
            applicationInfo: applicationInfo(),
            selectedMode: viewModel.preferences.dataMode,
            canCheckForUpdates: appUpdater.canCheckForUpdates
        )
        let menu = NSMenu(title: "TokChan")
        for descriptor in descriptors {
            switch descriptor {
            case let .information(text):
                let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            case let .diagnostics(messages):
                let item = NSMenuItem(title: "刷新详情", action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: "刷新详情")
                for message in messages {
                    let detail = NSMenuItem(title: message, action: nil, keyEquivalent: "")
                    detail.isEnabled = false
                    submenu.addItem(detail)
                }
                item.submenu = submenu
                menu.addItem(item)
            case .separator:
                menu.addItem(.separator())
            case let .submitAndRefresh(isEnabled):
                let item = NSMenuItem(
                    title: StatusMenuBuilder.title(for: descriptor) ?? "",
                    action: #selector(submitUsageAndRefreshStatistics(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.isEnabled = isEnabled
                menu.addItem(item)
            case let .refreshStatistics(isEnabled):
                let item = NSMenuItem(
                    title: StatusMenuBuilder.title(for: descriptor) ?? "",
                    action: #selector(refreshStatisticsNow(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.isEnabled = isEnabled
                menu.addItem(item)
            case let .dataMode(mode, isSelected, isEnabled):
                let item = NSMenuItem(
                    title: StatusMenuBuilder.title(for: descriptor) ?? "",
                    action: #selector(selectDataMode(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = mode.rawValue
                item.state = isSelected ? .on : .off
                item.isEnabled = isEnabled
                menu.addItem(item)
            case let .checkForUpdates(isEnabled):
                let item = NSMenuItem(
                    title: StatusMenuBuilder.title(for: descriptor) ?? "",
                    action: #selector(checkForUpdates(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.isEnabled = isEnabled
                menu.addItem(item)
            case .settings:
                menu.addItem(NSMenuItem(
                    title: "设置…",
                    action: #selector(openSettings(_:)),
                    keyEquivalent: ","
                ))
                menu.items.last?.target = self
            case .quit:
                menu.addItem(NSMenuItem(
                    title: "退出 TokChan",
                    action: #selector(quit(_:)),
                    keyEquivalent: "q"
                ))
                menu.items.last?.target = self
            }
        }
        return menu
    }

    private func synchronizeStatusItem() {
        updateStatusItem(with: viewModel.statusItemTitle)
    }

    private func updateStatusItem(with title: String?) {
        let presentation = StatusItemPresentation(statusTitle: title)
        statusItem.length = presentation.usesVariableLength
            ? NSStatusItem.variableLength
            : NSStatusItem.squareLength
        guard let button = statusItem.button else { return }
        button.title = presentation.title
        if presentation.usesVariableLength {
            button.attributedTitle = presentation.baselineAdjustedTitle(from: button.attributedTitle)
        }
        button.imagePosition = presentation.usesVariableLength ? .imageLeading : .imageOnly
        button.setAccessibilityLabel(presentation.accessibilityLabel)
    }

    @objc private func submitUsageAndRefreshStatistics(_ sender: Any?) {
        Task { await viewModel.submitUsageAndRefreshStatistics() }
    }

    @objc private func refreshStatisticsNow(_ sender: Any?) {
        Task { await viewModel.refreshStatisticsNow() }
    }

    @objc private func selectDataMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = DashboardDataMode(rawValue: rawValue) else { return }
        Task { await viewModel.selectDataMode(mode) }
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        appUpdater.checkForUpdates()
    }

    @objc private func openSettings(_ sender: Any?) {
        settingsAction.perform()
    }

    @objc private func quit(_ sender: Any?) {
        terminate()
    }

    private static func bundleApplicationInfo() -> String {
        let bundle = Bundle.main
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "TokChan"
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        return version.isEmpty ? name : "\(name) \(version)"
    }
}
