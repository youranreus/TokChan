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


### Scenario: Configurable status-item usage text and manual transfer actions

#### 1. Scope / Trigger

Use this contract when changing status-item title text, its Settings preferences, or the manual push/pull items in the secondary-click menu. The feature crosses SwiftUI Settings, UserDefaults, Dashboard cache state, Tokscale services, and the AppKit status item.

#### 2. Signatures

```swift
struct UserPreferences {
    var statusTextEnabled: Bool      // default false
    var statusTextTemplate: String  // default "{token} · {cost}"
    var statusTextPeriod: ProfilePeriod // default .day
}

enum StatusItemTextRenderer {
    static func render(template: String, data: DashboardData) -> String
}

@MainActor
extension DashboardViewModel {
    var statusItemTitle: String? { get }
    func statusItemTitle(for preferences: UserPreferences) -> String?
    func pushUsageNow() async
    func pullStatisticsNow() async
}
```

#### 3. Contracts

- Render every literal `{token}` with `DisplayFormatters.compactNumber(totalTokens)` and every `{cost}` with a status-item-only USD formatter pinned to `en_US`, so its symbol is `$` rather than locale-dependent `US$`. Preserve Dashboard's existing localized currency formatting, and preserve all unknown template text and placeholders verbatim; an empty result means icon-only.
- Derive the title only from a complete, same-account all/day/week/month cache. The configured scope selects a cached projection and never starts a request. Missing data hides the title; refresh and failure keep the old title until a complete batch replaces it.
- Observe saved preferences and cache publication in the one coordinator. `@Published` emits the incoming value from `willSet`, so preference-driven title updates must compute from the value delivered to `sink`, not reread the old stored property.
- Use `NSStatusItem.variableLength`, `.imageLeading`, and an accessibility label containing the summary when a nonempty title exists. Preserve AppKit's native attributed title and apply a `-1` point baseline offset to its full range so text sits slightly lower beside the icon. Clear the title, restore `squareLength` / `.imageOnly`, and use `TokChan` as the accessibility label otherwise.
- Build push/pull items into every dynamic secondary-click menu. Disable both while any explicit `DashboardOperation` is running.
- `pushUsageNow()` runs exactly one CLI submit and no profile fetch. `pullStatisticsNow()` forces exactly one complete profile batch and no submit. Success is silent; push failures join diagnostics as `即时推送`, while pull failures use the existing statistics diagnostic.

#### 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Preference keys missing | Disabled, default template, and `.day` |
| Saved period raw value invalid | Fall back to `.day` |
| Status text disabled, template empty, wrong account, or incomplete cache | Icon-only square status item |
| Unknown template placeholder | Preserve it verbatim; do not block Settings save |
| Cached refresh pending or failed | Keep the previous complete-batch title |
| Any explicit operation running | Disable both push and pull items |
| Push fails | No fetch; record a light push diagnostic |
| Pull fails | No submit; preserve old batch and statistics diagnostic |

#### 5. Good / Base / Bad Cases

- Good: save `.week` with `Weekly {token} / {cost}` and immediately recompute from the existing week cache without a request.
- Base: a migrated install has no new preference keys, so it remains icon-only until the user enables the feature.
- Bad: bind title computation to dashboard `selectedPeriod`, publish partial scope data, validate unknown placeholders, make push call the existing submit-plus-fetch refresh, or start an independent status-title polling loop.

#### 6. Tests Required

- Renderer: repeated known placeholders, unknown placeholders, plain/empty templates, zero values, compact token formatting, exact `$` cost formatting, and proof that Dashboard currency formatting is unchanged.
- Preferences: round-trip all three keys, missing-key defaults, and invalid-period fallback.
- Presentation: nil/empty/nonempty title, square versus variable length, image position, `-1` point baseline offset that preserves native title attributes, and accessibility text.
- Cache/title flow: complete same-account cache, missing/incomplete/wrong-account cache, incoming saved preferences, stale retention, and complete-batch replacement.
- Menu/actions: dynamic ordering with and without information, enabled/disabled descriptors, push performs submit with zero fetches, pull performs one batch with zero submits, duplicate operations are rejected, and failures enter diagnostics.

#### 7. Wrong vs Correct

#### Wrong

```swift
viewModel.$preferences.sink { [weak self] _ in
    self?.updateStatusItem(with: self?.viewModel.statusItemTitle) // reads the old willSet value
}
```

#### Correct

```swift
viewModel.$preferences.sink { [weak self] incoming in
    guard let self else { return }
    self.updateStatusItem(with: self.viewModel.statusItemTitle(for: incoming))
}
```
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
