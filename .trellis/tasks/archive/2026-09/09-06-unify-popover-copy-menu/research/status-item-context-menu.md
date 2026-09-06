# macOS status-item context-menu architecture research

_Date: 2026-09-06 · Scope: research only; no product code changed_

## Post-implementation correction from manual acceptance

The initial recommendation below correctly established the `NSStatusItem`/`NSPopover` ownership boundary, but its `popUpContextMenu` presentation detail was rejected in manual testing: it produces a cursor-anchored contextual menu rather than the required native status-bar drop-down.

The accepted implementation temporarily assigns the freshly built `NSMenu` to `statusItem.menu`, calls `NSStatusBarButton.performClick(nil)` so AppKit owns anchoring and selected-icon highlighting, and clears `statusItem.menu` when tracking ends so later left clicks continue toggling the popover. Settings opening likewise first invokes the SwiftUI Settings command through the standard Command-Comma main-menu key equivalent, with responder-chain selectors retained as the macOS 13 fallback. The user manually verified both behaviors on 2026-09-06.

This correction supersedes later `popUpContextMenu` and “never toggle `statusItem.menu`” recommendations in this research record; those lines remain as the original investigation history.

## Recommendation

Replace the SwiftUI `MenuBarExtra(.window)` scene with one app-owned `NSStatusItem` and one long-lived, transient `NSPopover` whose `contentViewController` is an `NSHostingController(rootView: DashboardView(...))`. Keep the existing SwiftUI `Settings` scene. Route the status-bar button's left and right mouse-up events through a small `@MainActor` AppKit coordinator:

- **left mouse-up:** toggle the existing popover using `popover.isShown`, `show(relativeTo:of:preferredEdge:)`, and `performClose(_:)`;
- **right mouse-up:** close the dashboard popover if necessary, rebuild/update an `NSMenu` from current view-model state, and display it as a contextual menu using the original event (`NSMenu.popUpContextMenu(_:with:for:)`);
- retain exactly one status item, popover, hosting controller, and dashboard view model for the app lifetime.

This is the smallest solution that uses only public, macOS 13-era APIs and gives deterministic ownership of both mouse buttons. Do **not** assign the context menu permanently to `statusItem.menu`: Apple defines that property as the drop-down menu displayed when the item is pressed/clicked, which would take over ordinary left-click behavior too.

Prefer an `NSApplicationDelegate` installed with `@NSApplicationDelegateAdaptor` as the composition/lifecycle owner. It can construct the shared model container synchronously, install the AppKit status-item coordinator in `applicationDidFinishLaunching`, and expose the same models to the retained SwiftUI `Settings` scene. This avoids creating an `NSStatusItem` as a side effect of SwiftUI `body` and avoids duplicate model instances.

## Why `MenuBarExtra(.window)` is insufficient

The public `MenuBarExtra` API does **not** expose a right-click/context-menu hook or its underlying `NSStatusItem`/button/window.

- Apple's description says `MenuBarExtra` is a scene rendering a persistent menu-bar control. The `.window` style renders its supplied content in a “popover-like window”; it does not document separate primary/secondary click content.
- The installed SwiftUI interface (macOS 13+) exposes content/label initializers and an optional `isInserted` binding only. `isInserted` controls whether the status item exists; it is not a presentation binding. There is no event, menu, status-item, or window accessor (local SDK `SwiftUI.swiftinterface`, `MenuBarExtra`, lines 1653–1738 in the installed macOS 26.2 SDK).
- The repository uses exactly this opaque surface at `TokChan/TokChanApp.swift:72-77`. Consequently, there is no supported point at which to attach an `NSMenu` to only the secondary click.

A SwiftUI `.contextMenu` on the dashboard content would apply only after the dashboard window is open; it does not attach to the menu-bar icon. A `.contextMenu` or `NSViewRepresentable` embedded in the label is also not a documented way to replace the scene-owned status-button event handling.

**Conclusion:** `MenuBarExtra(.window)` directly supports either its window-style content or menu-style content, but not two independently routed mouse buttons on its icon through public API.

## Preferred bridge in detail

### Status-button event routing

`NSStatusItem.button` is the supported customization surface. `NSStatusBarButton` is an `NSButton`, and therefore an `NSControl`; configure its target/action and call `sendAction(on: [.leftMouseUp, .rightMouseUp])`. In the action, inspect `NSApp.currentEvent?.type` (or pass the event classification into a pure routing helper).

Use the standard button with the existing template asset, tooltip/accessibility description “TokChan”, and variable/square status-item length as appropriate. Do not install a deprecated custom status-item view. Apple explicitly says template images render correctly in menu-bar states and appearances (`NSStatusBarButton.h:14-20`) and says behavior should be customized through `NSStatusItem.button` (`NSStatusItem.h:45-51, 83-88`). Keep a strong reference to the `NSStatusItem`; otherwise AppKit may remove it.

For right-click, leave `statusItem.menu == nil` and invoke the context menu only in the right-click branch. `NSMenu.popUpContextMenu(_:with:for:)` accepts the actual `NSEvent` and anchor view, preserving native contextual-menu placement/tracking. Close the popover before opening the menu so the two surfaces cannot overlap and panel visibility transitions remain unambiguous.

### Dashboard popover

Create one `NSPopover` with:

- `behavior = .transient`, which AppKit documents as closing after interaction outside the popover;
- `contentSize = NSSize(width: 380, height: 680)` and the existing `DashboardView` hosted by `NSHostingController`;
- the status button as positioning view and `.minY` as preferred edge;
- one delegate/coordinator to observe show/close transitions.

`NSPopover` is available far earlier than macOS 13. Apple documents `isShown`, explicit show/close, automatic positioning relative to the anchor view, and delegate notifications. AppKit may choose another edge if 680 points do not fit the current screen, which is safer than manually positioning an `NSPanel`.

The coordinator should toggle the same popover rather than construct a new hosting tree on every click. That preserves cached dashboard UI state, the selected range, scroll/expansion behavior until SwiftUI intentionally resets it, and the app-level `DashboardViewModel` shared with Settings.

### Dynamic right-click menu

Make the AppKit coordinator an `NSMenuDelegate` and update items in `menuNeedsUpdate(_:)`, or rebuild the short menu immediately before `popUpContextMenu`. This ensures the menu reads the latest:

1. disabled informational item containing the unified snapshot freshness text (`cacheSavedAt`, plus actual server data date when stale);
2. diagnostics item/submenu only when `diagnosticMessages` is nonempty (a submenu is simplest; use a dedicated hosted diagnostics panel only if selectable/copyable long text remains a requirement);
3. separator;
4. Settings;
5. Quit TokChan.

Keep freshness formatting in one shared pure formatter/presentation value used by both the dashboard header and menu, rather than retaining the current private `DashboardView.updateText` (`TokChan/Features/Dashboard/DashboardView.swift:222-230`). This prevents the two locations from drifting and makes date/locale/stale-date behavior unit-testable. Current diagnostic source state is already centralized in `DashboardViewModel.diagnosticMessages`; the existing UI consumes it at `DashboardView.swift:179-206`.

Settings should retain the project’s documented macOS 13 responder-chain behavior: activate the app, send `showSettingsWindow:`, then fall back to `showPreferencesWindow:`. The SwiftUI `Settings` scene remains the window owner. The existing implementation is at `DashboardView.swift:232-270`, and the compatibility rule is in `.trellis/spec/macos/swiftui-guidelines.md` under “Opening the settings scene”. Quit remains `NSApplication.shared.terminate(nil)`, currently at `DashboardView.swift:211-213`.

## Lifecycle implications

Panel visibility is behavioral state, not merely presentation polish in this project:

- `DashboardView` currently calls `panelDidAppear()`/`panelDidDisappear()` from SwiftUI lifecycle callbacks (`DashboardView.swift:53-61`).
- Those methods start loading/timer work and cancel only the visibility timer on close (`DashboardViewModel.swift:169-189`). They deliberately do not cancel an already-running refresh/submit operation.
- Unit tests assert that automatic refresh occurs only while visible (`TokChanTests/DashboardViewModelTests.swift:365-445`).
- The UI regression asserts left-click close/reopen and accumulated appearance/disappearance counts (`TokChanUITests/TokChanUITests.swift:4-35`).

For deterministic AppKit bridging, make **one layer only** responsible for visibility callbacks. Safest is the popover coordinator using `NSPopoverDelegate.popoverDidShow`/`popoverDidClose`, and remove the corresponding callbacks from `DashboardView`; alternatively retain SwiftUI callbacks only after an integration test proves they fire exactly once for every transient and explicit `NSPopover` close. Never call from both places, or timers/counts can duplicate. The coordinator path directly covers left-toggle close, outside-click transient close, right-click replacement by menu, and programmatic close.

The operation-banner requirement has an additional race that changing presentation alone does not solve. `clearOperationMessage()` refuses to clear a running operation, correctly preserving the operation (`DashboardViewModel.swift:338-341`), but if the panel closes while work is running, its later terminal result can otherwise be visible on reopen. Record a close/visibility generation (or a `discardTerminalOperationWhenComplete` flag) and publish terminal success/failure as `.idle` when that operation finishes while its originating panel has been dismissed. Closing must still cancel only the timer, not the operation. Add explicit tests for both (a) terminal message cleared on close and (b) running operation completes but leaves no stale banner on reopen.

## Comparison with alternatives

| Option | Advantages | Problems / risk | Verdict |
|---|---|---|---|
| **One `NSStatusItem` + `NSPopover` + `NSMenu`** | Public APIs; exact left/right routing; native anchoring/menu tracking; deterministic lifecycle; macOS 13 compatible; unit-testable coordinator | Replaces SwiftUI-owned popover-like window; requires AppKit coordinator and explicit lifecycle/accessibility work | **Recommended** |
| Keep `MenuBarExtra(.window)` and intercept events | Smaller apparent diff; preserves SwiftUI’s exact private window implementation | No public underlying status-item/button accessor; label hit-testing is undocumented; local/global event monitors require coordinate filtering and cleanup, can observe rather than own events, and may race SwiftUI’s own toggle; brittle across OS updates; hard to UI-test reliably | Reject |
| Two `MenuBarExtra`s or window/menu style switching | Stays declarative | Produces two items or requires removing/reinserting the icon; no stable one-icon secondary-click contract; likely flicker/state loss | Reject |
| `NSStatusItem` + custom `NSPanel` | Maximum window control, potentially closest visual emulation | More code for placement, spaces/screens, focus/key status, outside-click monitors, dismissal, and accessibility | Use only if `NSPopover` fails a demonstrated dashboard control/focus requirement |

The interception approach is specifically less safe than a small bridge: it depends on implementation details of a SwiftUI scene precisely where the public SDK is silent. It also makes a regression on macOS 13 more likely even if it happens to work on the development SDK.

## Testability plan

1. **Pure unit tests:** extract click classification (`leftMouseUp -> toggle`, `rightMouseUp -> contextual menu`, unrelated events ignored), unified freshness text, and dynamic menu descriptors into pure values/functions.
2. **Coordinator tests:** inject narrow actions/closures for show, close, settings, terminate, and menu presentation rather than invoking process termination in unit tests. Assert right-click closes an open popover before presenting the menu and left-click toggles only the popover. AppKit object smoke tests may use real `NSPopover`/`NSMenu` on `@MainActor`, but business assertions should not depend on a live menu bar.
3. **View-model tests:** retain the timer visibility tests above; add exactly-once/idempotence coverage if coordinator callbacks can repeat; add completed-operation and in-flight-operation dismissal tests.
4. **UI tests:** retain the current left-click close/reopen test and add `statusItem.rightClick()`, menu-item discovery, dynamic diagnostics visibility, Settings opening, and confirmation that a right click does not open the dashboard. Do not execute Quit in the same flow unless it is the final assertion. Preserve the status item’s accessible “TokChan” identity because the existing UI test locates `systemUI.menuBars.statusItems["TokChan"]` (`TokChanUITests.swift:12-18`).
5. **Manual macOS 13 pass:** verify template icon/highlight, left toggle, click-outside dismissal, right-click while open/closed, Settings activation/reopening, keyboard menu navigation, multiple displays/notches, light/dark mode, and the 380×680 panel near constrained screen edges.

`SettingsWindowActionTests.swift:7-21` currently only mirrors the dashboard tree for any native `Button`; after moving Settings out of the footer this test becomes misleading. Replace it with tests of the shared Settings action/coordinator and an integration/UI assertion that the Settings menu command opens/reuses the SwiftUI Settings window.

## Risks and mitigations

- **Visual/behavior delta from `.window`:** `NSPopover` is popover-like but may differ subtly in arrow, shadow, focus, or dismissal. Prototype on macOS 13 before broad refactoring; use `NSPanel` only for a concrete blocker.
- **Lifecycle double delivery:** avoid simultaneous SwiftUI and popover-delegate visibility ownership; make transitions idempotent and test counts.
- **Right-click menu tracking:** do not toggle `statusItem.menu` opportunistically; use the right-click event with `popUpContextMenu` and keep the button’s target/action stable.
- **Dynamic state ownership:** menu closures must not capture stale snapshots or create another view model. Read shared `@MainActor` model state when the menu opens.
- **Popover/menu overlap:** explicitly close the popover first. AppKit notes that interaction with a menu is not guaranteed to close a transient popover automatically (`NSPopover.h:44-46`).
- **Operation completion race:** closing while an operation runs requires deferred suppression of its terminal banner, not cancellation.
- **App startup composition:** installing AppKit objects from SwiftUI `body` risks duplicate status items as body reevaluates. Install once from application-delegate lifecycle and retain strongly.
- **macOS 13 Settings:** `openSettings` is macOS 14-only; keep the responder-chain fallback and the native `Settings` scene.

## Sources

### Apple documentation

- [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) — persistent menu-bar scene; Apple’s discussion describes `.window` for complex/data-rich content.
- [MenuBarExtraStyle.window](https://developer.apple.com/documentation/swiftui/menubarextrastyle/window) — renders content in a popover-like window.
- [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem) — menu-bar item created by `NSStatusBar`, customized through its button.
- [NSStatusBarButton](https://developer.apple.com/documentation/appkit/nsstatusbarbutton) — status-item appearance/behavior and template-image semantics.
- [NSControl.sendAction(on:)](https://developer.apple.com/documentation/appkit/nscontrol/sendaction(on:)) — configures mouse-event conditions that send target/action.
- [NSPopover](https://developer.apple.com/documentation/appkit/nspopover) — anchoring, automatic positioning, close behaviors, and lifecycle.
- [NSMenu](https://developer.apple.com/documentation/appkit/nsmenu) — native menu presentation and delegate update surface.

### Authoritative local SDK interfaces

Installed SDK examined via `xcrun --sdk macosx --show-sdk-path` (Xcode macOS 26.2 SDK):

- `SwiftUI.framework/.../SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface:1653-1738` — complete public `MenuBarExtra` initializer surface; macOS 13 availability and no secondary-click/status-button accessor.
- `AppKit.framework/Headers/NSStatusBarButton.h:14-20` — standard button and template-image behavior.
- `AppKit.framework/Headers/NSStatusItem.h:41-63, 81-89` — `menu`, supported `button`, and deprecated custom-view/old popup APIs.
- `AppKit.framework/Headers/NSPopover.h:37-50, 111-129, 164-190` — behaviors, content, `isShown`, anchoring, and close API.
- `AppKit.framework/Headers/NSMenu.h:71-78` — context-menu and positioned-menu popup methods (available before macOS 13).

### Repository/spec anchors

- `TokChan/TokChanApp.swift:5-87` — current model ownership, test dependency selection, `MenuBarExtra(.window)`, and Settings scene.
- `TokChan/Features/Dashboard/DashboardView.swift:53-61, 165-270` — fixed size/lifecycle, current footer diagnostics/update/Settings/Quit, and macOS 13 Settings fallback.
- `TokChan/Features/Dashboard/DashboardViewModel.swift:169-189, 338-341` — panel timer lifecycle and terminal-message clearing guard.
- `TokChanTests/DashboardViewModelTests.swift:365-445` — visibility/timer contracts.
- `TokChanUITests/TokChanUITests.swift:4-35` — real status-item left-click and panel lifecycle regression.
- `.trellis/spec/macos/swiftui-guidelines.md` — native macOS behavior, Settings compatibility, fixed dashboard viewport, and panel-specific timer lifecycle.
- `.trellis/spec/macos/testing-guidelines.md` — injected clocks/sleep boundaries and UI-test expectations.
- `TokChan.xcodeproj/project.pbxproj:182,199,253,267,280,293` — deployment target 13.0.
