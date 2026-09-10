# Design：新增默认时间粒度配置项

## 1. Architecture and boundaries

This feature is a local presentation preference plus one panel-open state reset. It spans four existing boundaries:

1. `UserPreferences` / `UserDefaultsPreferencesStore` own the durable `defaultPeriod` value.
2. `DashboardViewModel` owns `selectedPeriod` and the in-memory four-period batch.
3. `SettingsView` (Display tab) edits the preference immediately through the existing `updatePreferences(_:)` path.
4. `panelWillAppear()` — a new cache-only hook that `StatusItemCoordinator` calls immediately before `NSPopover.show` — applies the preference as the panel's starting scope; `panelDidAppear()` repeats the same idempotent application once the popover is on screen.

Explicitly unchanged: the `DashboardCacheSnapshot` schema, the application-level refresh scheduler, TTL/backoff, data-source (local/online) routing, `statusTextPeriod`, and the status-item title path.

## 2. Preference contract

Extend `UserPreferences` with:

- `defaultPeriod: ProfilePeriod` — default `.day`, declared as the last initializer parameter with a default value so every existing call site keeps compiling.

`UserDefaultsPreferencesStore`:

- New key `defaultPeriod`, appended to `Key.all` so `clear()` removes it.
- `load()` decodes `ProfilePeriod(rawValue:)` and falls back to `.day` both when the key is missing and when the stored raw value is unknown. This matches the existing `statusTextPeriod` precedent (`PreferencesStore.swift:115-116`).
- `save()` writes `rawValue`.
- `DashboardViewModel.normalized(_:)` passes the field through unchanged; it needs no trimming or validation because the type is a closed enum.

Compatibility: an upgraded install has no `defaultPeriod` key, decodes `.day`, and is otherwise untouched. Nothing in the snapshot schema changes, so existing `DashboardCacheSnapshot.selectedPeriod` round-trip behavior and its tests stay valid.

## 3. Panel-open reset contract

`panelWillAppear()` is a new side-effect-free entry point whose only job is to make the panel's scope equal `preferences.defaultPeriod`. It is invoked by `StatusItemCoordinator` before `NSPopover.show`, so the first frame the user sees is already the configured scope; `panelDidAppear()` (driven by `popoverDidShow`) keeps its visibility bookkeeping and calls the same application, so the pre-show and post-show paths cannot drift.

Required properties:

- **Synchronous single render.** The reset updates `selectedPeriod` and the derived display state (`profileState`, `identityProfile`) in the same MainActor turn, so SwiftUI renders once with the new scope. There must be no intermediate frame showing the previously restored scope.
- **Cache-only.** The reset consumes the in-memory batch exactly like `selectPeriod(_:)` does. It must issue zero Tokscale CLI/API calls, write zero cache snapshots, and must not start, stop, or accelerate the refresh schedule. This preserves the existing contract that statistics freshness is an application-level concern and that panel open/close changes no schedule.
- **Graceful miss.** If the target period is absent from the in-memory batch (incomplete/absent batch), the reset shows the loading state for that scope and waits for the application-level scheduler; it must not fabricate an independent scope request.
- **Idempotent across both hooks.** `panelWillAppear()` performs no visibility bookkeeping, so it may run before `panelDidAppear()` without changing `isPanelVisible` or `panelAppearanceCount`; the `guard !isPanelVisible` early return still prevents repeated work inside one continuous visible period. Re-opening the panel always re-applies the preference, by design (D2).
- **Manual switches survive within a session.** `selectPeriod(_:)` keeps its current behavior, including its cached-or-reload path, so the user can still switch scopes while the panel is open.

Implementation shape: extract the shared "apply this scope using the in-memory batch" logic into one private helper (`applyCachedPeriod(_:clearIdentityWhenUnavailable:)`) used by `selectPeriod(_:)` and both panel hooks, so the paths cannot drift. `selectPeriod(_:)` keeps its reload fallback; the panel hooks use the cache-only variant.

## 4. Restored snapshot scope

`DashboardViewModel.selectedPeriod` continues to hydrate from `DashboardCacheSnapshot.selectedPeriod` at init, preserving the documented snapshot-cache contract ("restore all available scopes on relaunch"). The preference is authoritative only for what the panel presents, which is why the reset lives on `panelDidAppear()` rather than replacing the hydration assignment.

Consequence: between app launch and the first panel open, `selectedPeriod` may still hold the restored snapshot scope. This is not user-visible because the panel is the only surface that renders it, and the reset runs before the panel's first rendered frame. No test should assert the preference value at init time.
Consequence: between app launch and the first panel open, `selectedPeriod` may still hold the restored snapshot scope. This must stay invisible to the user, which is why the preference is applied by `panelWillAppear()` **before** `NSPopover.show` instead of only from `popoverDidShow` after the first frame: the restored scope is never drawn. No test should assert the preference value at init time.

## 5. Configuration reset

`resetConfiguration` currently hardcodes `selectedPeriod = .all` after clearing stores. It becomes `selectedPeriod = preferences.defaultPeriod`. Because `preferences` has just been reloaded from a cleared store, this resolves to `UserPreferences.defaults` → `.day`, which is exactly the new-install behavior. No other reset step changes.

## 6. Settings UI contract

Display tab, new `Section("时间范围")` rendered before `Section("模型明细")`:

- `Picker("默认时间范围", selection: preferenceBinding(\UserPreferences.defaultPeriod))` over `ForEach(ProfilePeriod.allCases)`.
- `.pickerStyle(.menu)` — a pop-up select rather than the segmented tab-style control, so the four scopes read as one setting value instead of a tab bar. (The panel's own `period-picker` stays segmented; that surface is out of scope for this change.)
- `.accessibilityIdentifier("default-period")`.
- One caption line stating that opening the panel returns to this scope.
- Immediate persistence through the existing binding; no Save control, no CLI side effect, no cache write.

## 7. Trade-offs

| Choice | Reason | Cost |
|---|---|---|
| Force on every panel open (D2) | Matches the requested "默认" semantics; the panel always opens in the configured scope | A manual scope switch is not remembered across panel re-opens; this is a deliberate behavior change from today's persisted-selection behavior and must be stated in README and release notes |
| Cache-only reset (R4) | Preserves the "panel open starts no request" contract | If the batch is incomplete, the panel briefly shows a loading state instead of issuing its own request |
| Snapshot hydration unchanged | Avoids a cache schema/semantics change and keeps existing cache tests meaningful | The snapshot's stored scope no longer decides what the panel shows |

## 8. Rollback

Each stage is independently revertible:

- Preference/model changes compile and pass `PreferencesStoreTests` with no UI wiring.
- The panel-open reset is additive across two hooks; reverting it restores today's "remember last scope" behavior while leaving the preference and Settings control harmless.
- The Settings section is additive; removing it leaves the preference at its `.day` default.
- README and the release-notes fragment are documentation-only.

No migration is written, so no data rollback is required.
