# Implementation Plan：新增默认时间粒度配置项

Requirements: R1–R6 in `prd.md`. Design: `design.md`.

## 1. Extend preference persistence (R1, AC5, AC7)

- Add `defaultPeriod: ProfilePeriod` to `UserPreferences` (`TokChan/Shared/Services/PreferencesStore.swift:12`) as the last `init` parameter with default `.day`; keep it out of `normalizedClientIDs` logic.
- Add `Key.defaultPeriod = "defaultPeriod"` and append it to `Key.all`.
- `load()`: `defaults.string(forKey: Key.defaultPeriod).flatMap(ProfilePeriod.init(rawValue:)) ?? .day`.
- `save()`: write `preferences.defaultPeriod.rawValue`.
- Pass the field through `DashboardViewModel.normalized(_:)` (`TokChan/Features/Dashboard/DashboardViewModel.swift:1329`).
- Extend `TokChanTests/PreferencesStoreTests.swift`: round-trip a non-default value, assert the raw stored string, assert the missing-key default `.day`, and assert an unknown raw value falls back to `.day`. Add the key to the `clear()` assertion set.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' \
  -only-testing:TokChanTests/PreferencesStoreTests
```

Rollback point: this compiles and passes with zero UI or view-model behavior change. Revert alone if needed.

## 2. Extract the shared scope-apply helper (R3, R4)

- Add one private helper in `DashboardViewModel` that applies a `ProfilePeriod` from the in-memory batch only: set `selectedPeriod`; if a matching cached profile exists, set `profileState` and `identityProfile` in the same turn; otherwise set `profileState = .loading` and clear `identityProfile` — **never** start a request, never write a snapshot.
- Rewrite `selectPeriod(_:)` (`DashboardViewModel.swift:406`) to call the helper and keep its existing reload fallback (`reloadProfiles(force: false, automatic: true)`) plus `persistCurrentSnapshot()`.
- Keep the helper `private`; do not add a new public API.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' \
  -only-testing:TokChanTests/DashboardViewModelTests \
  -only-testing:TokChanTests/DashboardDataModeTests
```

Rollback point: `selectPeriod(_:)` behavior must be byte-for-byte identical before and after the extraction; this is the refactor-only step.

## 3. Force the preference on panel open (R3, R4, AC1–AC4, AC9)

- Add `panelWillAppear()` to `DashboardViewModel` (`DashboardViewModel.swift:303`): it calls the cache-only helper with `preferences.defaultPeriod` and does no visibility bookkeeping.
- In `StatusItemCoordinator` (`StatusItemCoordinator.swift:260`) call `viewModel.panelWillAppear()` inside the `show:` closure **before** `popover.show(...)`, so the first rendered frame already carries the configured scope instead of the scope restored from the snapshot.
- Keep `panelDidAppear()`'s guard, DEBUG `panelAppearanceCount` increment, and `isPanelVisible = true`, but have it call the same `panelWillAppear()` so the pre-show and post-show paths cannot drift.
- Do not call `persistCurrentSnapshot()` on either hook (the cache contract stays untouched and no write occurs on open).
- Add `DashboardViewModelTests` coverage:
  - panel open on a complete batch whose snapshot scope is `.all` and preference `.week` yields `selectedPeriod == .week`, `profileState.loadedValue?.period == .week`, matching `identityProfile`, in the same synchronous call;
  - `panelWillAppear()` alone settles the configured scope without incrementing `panelAppearanceCount`, and the following `panelDidAppear()` is idempotent (AC9);
  - manual `selectPeriod(.month)` followed by `panelDidDisappear()` + `panelDidAppear()` returns to the configured value (AC3);
  - panel open on a batch missing the configured period yields `.loading` and records zero events (AC4);
  - panel open records zero `submit`/`run`/`fetch`/`configure`/`disable` events and zero cache writes (AC4).
- Reuse the existing `EventRecorder` / `InMemoryCache` fixtures; extend the in-memory preferences fixture with a `defaultPeriod` value where a non-default is needed.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' \
  -only-testing:TokChanTests/DashboardViewModelTests \
  -only-testing:TokChanTests/OperationBannerLifecycleTests
```

Rollback point: this is the only step that changes observable panel behavior. Reverting just this step restores "remember last scope" while keeping the preference and Settings control.

## 4. Configuration reset follows the preference (R5, AC6)

- In `resetConfiguration` (`DashboardViewModel.swift:831`) replace `selectedPeriod = .all` with `selectedPeriod = preferences.defaultPeriod` (assignment stays after `preferences = preferencesStore.load()`).
- Extend the existing reset test to assert `selectedPeriod == .day` on a cleared store, and that a subsequent `panelDidAppear()` keeps `.day`.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' \
  -only-testing:TokChanTests/DashboardViewModelTests
```

## 5. Add the Display-tab control (R2, AC1, AC8)

- In `TokChan/Features/Settings/SettingsView.swift`, inside `displaySettings` (`:333`) add `Section("时间范围")` before `Section("模型明细")`:

```swift
Section("时间范围") {
    Picker("默认时间范围", selection: preferenceBinding(\UserPreferences.defaultPeriod)) {
        ForEach(ProfilePeriod.allCases) { period in
            Text(period.title).tag(period)
        }
    }
    .pickerStyle(.menu)
    .accessibilityIdentifier("default-period")

    Text("打开面板时回到该时间范围。")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

- Keep immediate persistence through `preferenceBinding`; add no Save control and no CLI action.
- Extend `TokChanUITests/TokChanUITests.swift` display-page coverage for the **pop-up select**: query `application.popUpButtons["default-period"]`, assert its `value` is 「日」, then `click()` the control and pick 「周」/「日」 from `application.menuItems[...]`, asserting `value` each time — without breaking the existing model-detail/client assertions.

Validation gate:

```bash
xcodebuild -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' build
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' \
  -only-testing:TokChanUITests
```

Note: the existing UI test skips when SystemUIServer does not expose the status item. Record whether it ran or skipped; a skip is not evidence for AC8.

## 6. Docs and release fragment (R6)

- `README.md`: document the new 「展示配置 → 时间范围」 setting and that opening the panel returns to the configured range (see the `README.md:61` 「用量面板」 paragraph and the settings list around `README.md:29-42`).
- Add `release-notes/fragments/20260910-default-panel-period.json`:

```json
{ "category": "新增", "summary": "新增面板默认时间范围配置，打开面板时回到所选范围" }
```

Validation gate: `python3 -c "import json,glob;[json.load(open(f)) for f in glob.glob('release-notes/fragments/*.json')]"`

## 7. Full-scope check before completion

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS'
```

Assert explicitly:

- AC1–AC8 in `prd.md` each map to a passing test or a recorded manual verification.
- `TokChanTests/DashboardCacheStoreTests` still passes unchanged (no cache schema change).
- `testPanelVisibilityNeverStartsOrStopsStatisticsScheduling` still records zero events across panel open/close (`DashboardViewModelTests.swift:1487`).
- No new Tokscale request, cache write, or scheduler change was introduced on the panel-open path.
- If behavior differs from `.trellis/spec/macos/data-persistence.md` 「Dashboard snapshot cache」 or 「Status-item presentation preferences」, update the spec in Phase 3.

## Risky files

| File | Risk |
|---|---|
| `TokChan/Features/Dashboard/DashboardViewModel.swift` | `selectedPeriod`, `selectPeriod(_:)`, `panelWillAppear()`, `panelDidAppear()`, `resetConfiguration`, `normalized(_:)` — the shared scope helper must not alter scheduler, request, or cache behavior |
| `TokChan/Shared/StatusItemCoordinator.swift` | The pre-show `panelWillAppear()` call must stay before `popover.show`; moving it after the show (or into `popoverDidShow`) reintroduces the first-frame flash |
| `TokChan/Shared/Services/PreferencesStore.swift` | `Key.all` omission would leave the key behind on `clear()`; wrong fallback would break upgrade compatibility |
| `TokChan/Features/Settings/SettingsView.swift` | The Display-tab picker must keep `.pickerStyle(.menu)`; reverting to `.segmented` restores the tab-style control the user rejected |
| `TokChanTests/DashboardViewModelTests.swift` | Existing fixtures construct `UserPreferences` explicitly; keep them source-compatible by relying on the new parameter's default |
