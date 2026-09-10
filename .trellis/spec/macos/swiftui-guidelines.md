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
For the `LSUIElement` app, activate `NSApplication` immediately before showing a previously hidden transient popover, then make the newly created popover window key. Activation alone does not guarantee that the status-item-anchored window becomes key; without both steps, AppKit may not establish outside-click dismissal even though `behavior == .transient`. Closing an already shown popover must not activate the app or change key-window state. Keep the `activate → show → makeKey` / close orchestration injectable and test its exact ordering; do not replace this with local or global event monitors.

Let AppKit's `NSPopover` remain the only root-background owner. `DashboardView` must not paint an opaque full-bounds background or add a second SwiftUI/AppKit material layer; otherwise the content rectangle no longer matches the system-rendered arrow in light and dark appearances. Local card and banner backgrounds remain appropriate.

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
    func submitUsageAndRefreshStatistics() async
    func refreshStatisticsNow() async
}
```

#### 3. Contracts

- Render every literal `{token}` with `DisplayFormatters.compactNumber(totalTokens)` and every `{cost}` with a status-item-only USD formatter pinned to `en_US`, so its symbol is `$` rather than locale-dependent `US$`. Preserve Dashboard's existing localized currency formatting, and preserve all unknown template text and placeholders verbatim; an empty result means icon-only.
- Derive the title only from a complete, same-account all/day/week/month cache. The configured scope selects a cached projection and never starts a request. Missing data hides the title; refresh and failure keep the old title until a complete batch replaces it.
- Observe saved preferences and cache publication in the one coordinator. `@Published` emits the incoming value from `willSet`, so preference-driven title updates must compute from the value delivered to `sink`, not reread the old stored property.
- Use `NSStatusItem.variableLength`, `.imageLeading`, and an accessibility label containing the summary when a nonempty title exists. Preserve AppKit's native attributed title and apply a `-1` point baseline offset to its full range so text sits slightly lower beside the icon. Clear the title, restore `squareLength` / `.imageOnly`, and use `TokChan` as the accessibility label otherwise.
- Build both manual transfer items into every dynamic secondary-click menu, titled through `StatusMenuBuilder.title(for:)`. Disable both while any explicit `DashboardOperation` is running.
- There is no submit-only entry point. `submitUsageAndRefreshStatistics()` runs exactly one CLI submit and then one forced complete batch; `refreshStatisticsNow()` forces exactly one complete batch and runs no submit. `StatusMenuBuilder.title(for:)` is the only definition of their user-facing titles (“提交并拉取” and “拉取远程数据”), and the Dashboard header button reuses it so the panel and the menu cannot drift apart.
- Freshness copy describes the client read, never server aggregation. `RelativeDateTimeFormatter` renders a sub-minute or clock-rolled-back age as “0 秒后”, which reads as a future event, so any age below 60 seconds must collapse to a fixed “统计刚刚读取” instead.
- Manual actions capture the account, generation, and CLI context at start. If any of them changes while the action is suspended, the action finishes as superseded and must not read or publish for the new account.
- Success is silent. Submit failures publish `submitErrorMessage` into diagnostics as `用量提交：…` so a failure started from a closed popover is still discoverable; fetch failures use the existing statistics diagnostic.

#### 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Preference keys missing | Disabled, default template, and `.day` |
| Saved period raw value invalid | Fall back to `.day` |
| Status text disabled, template empty, wrong account, or incomplete cache | Icon-only square status item |
| Unknown template placeholder | Preserve it verbatim; do not block Settings save |
| Cached refresh pending or failed | Keep the previous complete-batch title |
| Any explicit operation running | Disable both manual transfer items |
| Submit fails | No fetch; record a `用量提交：…` diagnostic so a closed panel still surfaces it |
| Submit succeeds but fetch fails | Keep the old batch and `fetchedAt`; report partial success without claiming the server is updated |
| Refresh-only fails | No submit; preserve old batch and statistics diagnostic |
| Account or CLI context changes mid-action | Finish as superseded; never read or publish for the new account |

#### 5. Good / Base / Bad Cases

- Good: save `.week` with `Weekly {token} / {cost}` and immediately recompute from the existing week cache without a request.
- Base: a migrated install has no new preference keys, so it remains icon-only until the user enables the feature.
- Bad: bind title computation to dashboard `selectedPeriod`, publish partial scope data, validate unknown placeholders, reintroduce a submit-only menu entry, or start an independent status-title polling loop.

#### 6. Tests Required

- Renderer: repeated known placeholders, unknown placeholders, plain/empty templates, zero values, compact token formatting, exact `$` cost formatting, and proof that Dashboard currency formatting is unchanged.
- Preferences: round-trip all three keys, missing-key defaults, and invalid-period fallback.
- Presentation: nil/empty/nonempty title, square versus variable length, image position, `-1` point baseline offset that preserves native title attributes, and accessibility text.
- Cache/title flow: complete same-account cache, missing/incomplete/wrong-account cache, incoming saved preferences, stale retention, and complete-batch replacement.
- Menu/actions: dynamic ordering with and without information, enabled/disabled descriptors, submit-and-refresh orders exactly `submit` then one forced batch, refresh-only performs one batch with zero submits, duplicate operations are rejected, an account switch during a suspended submit publishes nothing for the new account, and submit failures enter diagnostics.

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
Only `NSPopoverDelegate.popoverDidShow` and `popoverDidClose` may call `DashboardViewModel.panelDidAppear()` and `panelDidDisappear()`. The status-item coordinator additionally calls `panelWillAppear()` inside the `show:` action, immediately before `popover.show(...)`; that call performs no visibility bookkeeping and exists only so the popover's first frame already shows the configured scope. `DashboardView` must not duplicate those callbacks with `onAppear`/`onDisappear`; SwiftUI view lifecycle is not authoritative popover visibility.

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

Ordinary `UserDefaults` preferences persist from control bindings immediately. Do not put a shared Save footer across Settings tabs. Operations with CLI side effects own a clearly scoped action in their tab; TokChan's autosubmit page uses “应用自动提交设置”, while General and About have no submit action. A view-owned autosubmit draft accepts a later status read only while pristine and is reset from confirmed status after a successful apply.

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

`ClientIcon` is the single client-ID-to-asset registry and visual treatment for Dashboard and Settings. Keep its authoritative ID set aligned with Tokscale's `SUPPORTED_CLIENT_TYPES`; explicit aliases may share one asset only for the same product or an upstream-documented compatibility mark. Keep distinct products distinct: `codebuddy` resolves to `client-codebuddy`, while `codebuff` resolves to `client-codebuff`. Apply the macOS-app-style rounded mask and subtle shadow inside `ClientIcon`, not independently at call sites. When adding an externally sourced icon, bundle it in the asset catalog, retain the original under `Resources/ClientOriginals`, record URL and SHA-256 in `provenance.json`, and do not imply that Tokscale's MIT license covers an external image. Asset tests must assert full authoritative mapping coverage and successful bundle loading.

Check light and dark renderings, zero/absent breakdown data, long client lists, and rapid scope changes. DashboardLayoutTests renders the real SwiftUI view at its fixed dimensions without remote dependencies.

Cache-first loading keeps the header button reserved for explicit submit/refresh feedback. A silent read with cached content must not spin or disable that button, clear metrics, reset the selected scope, or show a success/error banner. First load without data may use the existing loading/failure state.

**Distinguish this from the intentional panel-open reset.** The rule above constrains silent background reads. `panelWillAppear()` deliberately re-applies `UserPreferences.defaultPeriod` before the popover is shown, and `panelDidAppear()` repeats it, so the selected scope does change on every open; that reset is cache-only, issues no request, and writes no snapshot. Keep the pre-show call ahead of `popover.show`, otherwise the snapshot-restored scope is drawn first. Do not delete the reset to satisfy the rule above, and do not implement it by spawning a read. See `.trellis/spec/macos/data-persistence.md` → 「Scenario: Panel default period preference」.

Popover delegate callbacks own presentation state only: visibility, the presentation generation, and banner lifetime. They must never start, stop, or reschedule statistics refresh, and they must never read autosubmit status. The five-minute schedule belongs to the application-level scheduler described in `data-persistence.md`, so a closed panel keeps the status-item title current. A completed manual-operation banner clears on close; if closing races with an in-flight operation, its eventual result remains available to non-dashboard consumers but must not appear after the popover is reopened.

The application delegate owns the whole background lifecycle: build the status-item coordinator first so it is already subscribed before any background publication, register the `NSWorkspace.didWakeNotification` observer, then start the scheduler exactly once. Wake performs a single freshness evaluation and never replays missed intervals. Wrap the notification in a small owner such as `SystemWakeObserver` whose `start()` is idempotent and whose `stop()`/`deinit` remove the token; a raw `addObserver` call in `applicationDidFinishLaunching` leaks a registration and can double-fire after a relaunch cycle.

The Settings window reports visibility transitions (`settingsDidBecomeVisible()` / `settingsDidBecomeHidden()`) rather than calling the combined loader from `.task`. Because `.task`, `onAppear`, and `scenePhase` can all fire for one presentation, the view model must collapse them so one continuous visible period reads autosubmit status and Cursor session status exactly once each. Cursor checking, connected, explicit-login-needed, and indeterminate retry-only states remain Settings-specific; onboarding continues to render its optional explicit login independently. Closing Settings cancels the presentation check and clears transient login feedback. In the shared Cursor row, Settings removes the `（可选）` suffix; both the checking spinner and `已登录` use the same trailing slot as `自动登录`, with no duplicate status row below. Onboarding retains the suffix.

The first-use welcome now has three steps: data mode, account connection, and first submission. Render the mode step first with local as the default and recommended choice; choosing local completes initialization immediately and enters the panel without an account, while choosing online continues into the existing two-step flow. Keep the step indicator's active count derived from `firstUseOnboardingState`, including the `.modeSelection` case.

In first-use account entry, use one shared control height for the rounded username field and both large actions. Put “继续” and “识别本机登录” in equal flexible columns, expand each label across its column, and retain the primary/default versus secondary hierarchy so intrinsic button widths cannot create asymmetric blank space in the 380×680 viewport.


### Scenario: Status-menu data mode, application info, and update rows

#### 1. Scope / Trigger

Use this contract when changing the secondary-click status menu's information rows, its data-mode selector, or its update action. These rows observe existing state; they never introduce a second updater or a second refresh path.

#### 2. Signatures

```swift
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

@MainActor extension StatusMenuBuilder {
    static func descriptors(
        freshness: String?,
        diagnostics: [String],
        actionsEnabled: Bool,
        applicationInfo: String? = nil,
        selectedMode: DashboardDataMode? = nil,
        canCheckForUpdates: Bool = false
    ) -> [StatusMenuDescriptor]
    static func title(for descriptor: StatusMenuDescriptor) -> String?
}
```

#### 3. Contracts

- Put the application name and version row first, then freshness, then diagnostics. The name and version come from `CFBundleDisplayName`/`CFBundleName` and `CFBundleShortVersionString`; never hard-code them.
- Render the data-mode group as two independently selectable items with a checkmark on the persisted `preferences.dataMode`. Both are disabled while an explicit operation runs, and selecting one routes through `DashboardViewModel.selectDataMode(_:)`, the same entry point Settings uses, so the two surfaces cannot diverge.
- The update row reuses the existing `AppUpdating` boundary and its `canCheckForUpdates`; do not construct another `SPUStandardUpdaterController`. Keep the action's enabled state derived from that property at menu-build time.
- Rebuild the whole descriptor list on every secondary click so freshness, diagnostics, application info, and mode selection are never startup snapshots.
- The dashboard panel must not duplicate these actions; the status menu stays the single owner of diagnostics, mode selection, update, Settings, and Quit.

#### 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| No freshness or diagnostics | Omit those rows; keep the mode group and update action |
| Explicit operation running | Disable both transfer items and both mode items |
| Updater cannot check | Show the row disabled rather than hiding it |
| Missing version key | Fall back to the bundle name alone |
| Local mode selected | Check the local item and leave the online transfer actions available |

#### 5. Good / Base / Bad Cases

- Good: the menu shows “TokChan 1.0.12”, the freshness row, both transfer actions, a checkmark on the active mode, and an enabled update action.
- Base: a build without a version string shows the name only and keeps every action usable.
- Bad: hard-coding the version, creating a second updater, letting the menu and Settings persist the mode independently, or building the menu once and caching it.

#### 6. Tests Required

- Descriptor ordering and titles for application info, freshness, diagnostics, mode items, update, Settings, and Quit.
- Mode items: correct `isSelected` state for each persisted mode, both disabled while an operation runs, and selection routed to `selectDataMode(_:)`.
- Update row: enabled/disabled follows `canCheckForUpdates`, and invoking it forwards exactly once to the injected updater.
- Bundle info: display-name precedence, version suffix, and the name-only fallback.

#### 7. Wrong vs Correct

#### Wrong

```swift
// A second updater and a hard-coded version drift apart from the app bundle.
let item = NSMenuItem(title: "TokChan 1.0.0", action: #selector(update), keyEquivalent: "")
```

#### Correct

```swift
applicationInfo: applicationInfo(),   // reads CFBundleDisplayName + CFBundleShortVersionString
canCheckForUpdates: appUpdater.canCheckForUpdates
```
Use one snapshot-freshness formatter for both the dashboard header and the dynamically built status menu. It reports the last successful statistics fetch and includes the selected server `dateRange.end` when that day differs from today. Compare the server `yyyy-MM-dd` string against today using a Gregorian calendar in the user's local timezone, regardless of the user's preferred calendar. No successful snapshot means no fabricated freshness item. Statistics/status/persistence failures remain diagnostics in the status menu; explicit operation failures retain normal in-panel feedback while the originating popover remains visible.
