# SwiftUI Guidelines

## View structure

- Use SwiftUI with value-type `View` structs.
- Keep `body` focused on layout and composition.
- Extract private computed subviews only when it improves readability or removes meaningful duplication.
- Prefer small feature views over a generic component library at project start.
- Use `private` helpers and subviews by default.

## State in views

- Use `@State` for simple view-owned UI state.
- Use `@Binding` when a child edits state owned by its parent.
- Use observable view models for async loading, persistence coordination, or multi-step business logic.
- Keep side effects in `.task`, button actions, or view models; do not trigger side effects while computing `body`.

## macOS UI patterns

- Prefer native macOS controls and window behavior over iOS-style interaction patterns.
- Use `NavigationSplitView` when the app has sidebar/detail structure; use `NavigationStack` only for clearly hierarchical flows.
- Keep navigation state explicit when screens need deep linking or restoration.
- Avoid stringly typed route identifiers; prefer enums or typed values once routing grows.

### Status-item and popover ownership

The application delegate must retain exactly one coordinator that owns one `NSStatusItem`, one `.transient` `NSPopover`, and one hosting controller for the 380×680 `DashboardView`. Do not use `MenuBarExtra(.window)`, assign a persistent `statusItem.menu`, or add a global event monitor.

Route status-button mouse-up events explicitly: left-click toggles the existing popover; right-click closes it first, builds an `NSMenu` from current model state, temporarily assigns it to `statusItem.menu`, and calls the status button's `performClick`. Clear the assignment when menu tracking ends so left-click remains the popover action. Do not use `popUpContextMenu` or coordinate-positioned `NSMenu.popUp`: the required surface is a native status-item menu, anchored and highlighted by AppKit. The status menu owns diagnostics, Settings, and Quit, and is rebuilt on every secondary click so freshness and diagnostics are not startup snapshots.

Only `NSPopoverDelegate.popoverDidShow` and `popoverDidClose` may call `DashboardViewModel.panelDidAppear()` and `panelDidDisappear()`. `DashboardView` must not duplicate those callbacks with `onAppear`/`onDisappear`; SwiftUI view lifecycle is not authoritative popover visibility.

### Native preferences toolbar

For multi-section app preferences, keep the SwiftUI `Settings` scene and make its root navigation a `TabView`. Declare each preference page with an SF Symbol `Label` in `.tabItem`; macOS promotes these items into the window's native preferences toolbar and owns selection, hover, spacing, titlebar material, separators, traffic lights, and dark mode.

```swift
Settings {
    TabView(selection: $selectedTab) {
        GeneralSettingsView()
            .tabItem { Label("常规", systemImage: "slider.horizontal.3") }
            .tag(SettingsTab.general)

        AboutSettingsView()
            .tabItem { Label("关于", systemImage: "info.circle") }
            .tag(SettingsTab.about)
    }
}
```

Do not simulate this navigation with an in-content `HStack`, buttons, segmented controls, rounded rectangles, or custom material. Use AppKit `NSToolbar` bridging only if the native SwiftUI `Settings` + `TabView` behavior cannot meet a concrete requirement.

### Opening the settings scene

SwiftUI-originated controls may use `@Environment(\.openSettings)` on macOS 14 and newer, with the environment property isolated in an `@available(macOS 14.0, *)` view. From the AppKit status menu, activate the app and first invoke the SwiftUI-owned Settings command via the main menu's standard Command-Comma key equivalent; this reliably reaches the Settings scene without title matching. If the command is unavailable, send `showSettingsWindow:` through the responder chain and fall back to `showPreferencesWindow:` only when unhandled for macOS 13 compatibility.

In every path, keep the SwiftUI `Settings` scene as the owner of the settings window, native chrome, and traffic-light controls.

Required checks:

- Build using the project's minimum macOS deployment target.
- Verify opening settings from the menu bar when the app is not active.
- Verify reopening an existing settings window brings it forward.
- Keep the `Settings` scene as the owner of native window chrome and traffic-light controls.
## Previews

- Add SwiftUI previews for non-trivial screens and reusable components.
- Previews should use lightweight sample data and must not perform live networking.

## Accessibility

- Provide accessible labels for icon-only buttons and custom controls.
- Respect system font sizing, dark mode, keyboard navigation, and pointer-focused interaction.
- Use system colors where possible so dark mode and contrast settings work by default.

## Dashboard viewport contract

The 380×680 dashboard popover has a fixed outer VStack. Identity/status (including shared snapshot freshness), the all/day/week/month segmented picker, metrics, five-category breakdown, and client section heading stay outside scrolling. Only client cards use ScrollView/LazyVStack. There is no dashboard footer: diagnostics, Settings, and Quit belong to the secondary-click status menu. Bound long feedback text so failures cannot consume the entire viewport.

Each client defaults to its top five models in existing token-descending order. Expand/collapse affects visible rows only. Reset the client subtree identity on scope change so expansion and scroll position reset. Use Tokens in user-facing copy.

Check light and dark renderings, zero/absent breakdown data, long client lists, and rapid scope changes. DashboardLayoutTests renders the real SwiftUI view at its fixed dimensions without remote dependencies.

Cache-first loading keeps the header button reserved for explicit submit/refresh feedback. A silent read with cached content must not spin or disable that button, clear metrics, reset the selected scope, or show a success/error banner. First load without data may use the existing loading/failure state.

Popover delegate callbacks start and stop the five-minute refresh timer. Closing the popover stops future timer triggers but may let an already-started, time-bounded batch or manual operation finish. A completed manual-operation banner clears on close; if closing races with an in-flight operation, its eventual result remains available to non-dashboard consumers but must not appear after the popover is reopened.

Use one snapshot-freshness formatter for both the dashboard header and the dynamically built status menu. It reports the last successful statistics fetch and includes the selected server `dateRange.end` when that day differs from today. Compare the server `yyyy-MM-dd` string against today using a Gregorian calendar in the user's local timezone, regardless of the user's preferred calendar. No successful snapshot means no fabricated freshness item. Statistics/status/persistence failures remain diagnostics in the status menu; explicit operation failures retain normal in-panel feedback while the originating popover remains visible.
