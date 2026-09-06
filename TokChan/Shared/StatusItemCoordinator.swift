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
    case push(isEnabled: Bool)
    case pull(isEnabled: Bool)
    case settings
    case quit
}

enum StatusMenuBuilder {
    static func descriptors(
        freshness: String?,
        diagnostics: [String],
        actionsEnabled: Bool
    ) -> [StatusMenuDescriptor] {
        var items: [StatusMenuDescriptor] = []
        if let freshness { items.append(.information(freshness)) }
        if !diagnostics.isEmpty { items.append(.diagnostics(diagnostics)) }
        if !items.isEmpty { items.append(.separator) }
        items.append(.push(isEnabled: actionsEnabled))
        items.append(.pull(isEnabled: actionsEnabled))
        items.append(.separator)
        items.append(.settings)
        items.append(.quit)
        return items
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
    private let terminate: () -> Void
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let hostingController: NSHostingController<AnyView>
    private var transientStatusMenu: NSMenu?
    private var cancellables: Set<AnyCancellable> = []

    init(
        viewModel: DashboardViewModel,
        settingsAction: SettingsWindowAction,
        terminate: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.settingsAction = settingsAction
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
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            }
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
            actionsEnabled: !viewModel.operation.isRunning
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
            case let .push(isEnabled):
                let item = NSMenuItem(
                    title: "立刻推送",
                    action: #selector(pushUsageNow(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.isEnabled = isEnabled
                menu.addItem(item)
            case let .pull(isEnabled):
                let item = NSMenuItem(
                    title: "立刻拉取",
                    action: #selector(pullStatisticsNow(_:)),
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
        button.imagePosition = presentation.usesVariableLength ? .imageLeading : .imageOnly
        button.setAccessibilityLabel(presentation.accessibilityLabel)
    }

    @objc private func pushUsageNow(_ sender: Any?) {
        Task { await viewModel.pushUsageNow() }
    }

    @objc private func pullStatisticsNow(_ sender: Any?) {
        Task { await viewModel.pullStatisticsNow() }
    }

    @objc private func openSettings(_ sender: Any?) {
        settingsAction.perform()
    }

    @objc private func quit(_ sender: Any?) {
        terminate()
    }
}
