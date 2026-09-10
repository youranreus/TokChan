# Implementation Plan：客户端列表展示过滤配置

## 1. Extend and test preference persistence

- Add the three display preference fields and backward-compatible defaults to `UserPreferences`.
- Add UserDefaults keys and round-trip logic, storing hidden client IDs as a stable sorted string array.
- Preserve the fields in `DashboardViewModel.normalized(_:)`, trimming/removing invalid hidden IDs.
- Update existing preference fixtures/builders that construct `UserPreferences` explicitly.
- Extend `PreferencesStoreTests` for round trip and missing-key compatibility.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -only-testing:TokChanTests/PreferencesStoreTests
```

Rollback point: preference model/store changes compile and pass independently before UI wiring.

## 2. Add pure display projection and candidate derivation

- Add a focused Dashboard feature helper that filters client IDs and zero-cost model rows without changing source models.
- Expose a deterministic `DashboardViewModel.availableClientIDs` union from all cached periods plus persisted selections.
- Expose or invoke the pure projection from Dashboard presentation code.
- Add focused unit tests for default, independent, and combined filtering; ordering/totals preservation; empty-model client retention; and multi-period candidate union.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -only-testing:TokChanTests/DashboardDisplayFilterTests -only-testing:TokChanTests/DashboardViewModelTests
```

Rollback point: projection stays isolated from `DashboardData` aggregation and cache serialization.

## 3. Add the Display Settings page

- Add a `display` case and native “展示配置” tab to `SettingsView`.
- Add grouped sections for the zero-cost model switch, client master switch, multi-select client rows, and no-candidate guidance.
- Implement set membership bindings through `updatePreferences(_:)`; selections remain retained while the master switch is off and become editable again when it is re-enabled.
- Add stable accessibility identifiers for the page and key controls.
- Collapse candidate rows while the master switch is off without clearing persisted selections; restore them when re-enabled.
- Keep ordinary preferences immediate-save with no shared Save footer.

Validation gate:

- Build the app at the existing macOS deployment target.
- Render/open Settings and verify the native toolbar tab, empty candidate state, multi-selection, and immediate persistence behavior.

## 3.1 Restore switch interaction and align client icons

- Render every candidate membership control as an independent native switch with `ClientIcon`, while keeping the separate master enable switch.
- Add a dedicated `client-codebuddy` asset without aliasing it to `codebuff`.
- Audit Tokscale's current `SUPPORTED_CLIENT_TYPES`, add explicit mappings for every authoritative ID, and bundle missing unique product assets.
- Reuse assets only for documented same-product/compatibility IDs; record source URLs and SHA-256 provenance for external assets.
- Apply the shared macOS-app-style rounded mask and subtle shadow inside `ClientIcon`.
- Extend mapping and asset-loading tests across the full authoritative ID set.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -only-testing:TokChanTests/TokenBreakdownTests
```

## 4. Wire Dashboard rendering and empty states

- Render the projected client list while retaining the original `DashboardData` for metrics, status text, cache, and refresh behavior.
- Preserve existing source-empty copy.
- Add distinct filter-empty copy when nonempty source clients are all hidden.
- Ensure model expansion counts and rows operate on the projected model list.
- Extend layout/UI tests where practical for the new empty state and settings controls.

## 5. Full verification

Run the complete project test suite:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS'
```

Review gates:

- Check `git diff` for accidental cache/API/CLI or status-item behavior changes.
- Confirm missing UserDefaults keys preserve current display.
- Confirm all/day/week/month candidate union and retained absent selections.
- Confirm both filters update the open dashboard immediately and compose correctly.
- Confirm source arrays, totals, percentages, and ordering remain unchanged.
- Inspect Settings and Dashboard in light/dark appearance at their existing window sizes.

## Risky files

- `TokChan/Shared/Services/PreferencesStore.swift`: constructor fan-out and upgrade defaults.
- `TokChan/Features/Dashboard/DashboardViewModel.swift`: cached-profile derivation must not alter refresh/cache contracts.
- `TokChan/Features/Dashboard/DashboardView.swift`: source-empty and filter-empty rendering must remain distinct.
- `TokChan/Features/Settings/SettingsView.swift`: adding a toolbar tab must preserve native Settings navigation and existing autosubmit apply behavior.
