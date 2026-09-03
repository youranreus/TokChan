# TokChan implementation plan

## 1. Project skeleton

- Create `TokChan.xcodeproj` with a macOS 13 application target, unit-test target, and UI-test target.
- Add the SwiftUI app entry using `MenuBarExtra` with `.window` style.
- Configure `LSUIElement` and keep App Sandbox disabled for the documented CLI integration requirement.
- Add deterministic assets and sample fixtures needed by previews and tests.

Validation:

```bash
xcodebuild -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' build
```

## 2. Models and service boundaries

- Define tolerant Codable models for the public profile and autosubmit JSON contracts.
- Map transport data into overview and grouped client/model display models.
- Implement and unit-test token aggregation, percentage calculation, sorting, number/currency/date formatting.
- Define API, CLI, preferences, and executable-location protocols only at the external seams needed by tests.

## 3. External integrations

- Implement the URLSession profile client with encoded username, status validation, and useful error mapping.
- Implement `NpxLocator` with saved path, inherited and common paths, NVM discovery, and executable validation.
- Implement safe `Process` execution with argument arrays, stdout/stderr capture, timeout/cancellation, and no shell interpolation.
- Implement validated command builders for whoami, submit, autosubmit status, enable, disable, and run-now.
- Implement the UserDefaults preference store without token access.

## 4. View-model workflows

- Implement read-only panel-open loading of profile and autosubmit status.
- Implement manual submit-then-profile-refresh ordering.
- Implement autosubmit enable, disable, configure, and run-now flows with status reload.
- Serialize mutating CLI work, ignore stale loads, and expose explicit loading, empty, error, and success states.
- Add focused fake-service tests for ordering, concurrency, and failure behavior.

## 5. Compact menu panel and settings

- Build the fixed-width, bounded-height vertical dashboard with header and metric grid.
- Build the autosubmit status strip and configuration UI for interval, clients, and date filters.
- Build the client-grouped model list with tokens, cost, percentage, and descending sort.
- Add loading, empty, stale, invalid-user, missing-npx, CLI-failure, and network-failure states.
- Add settings and quit actions, keyboard focus, accessibility labels, dark mode support, and deterministic previews.

## 6. Full verification

- Run unit and UI tests without real network or CLI effects.
- Run clean macOS build and test commands.
- Launch the Debug app locally and visually verify panel size, scrolling, dark and light appearance, and representative long lists.
- Exercise read-only status against the local Tokscale installation; do not mutate the user's real autosubmit configuration during automated verification.
- Run `git diff --check` and Trellis quality review before commit.

## 7. Acceptance feedback polish

- Add a compact Codable dashboard snapshot store under the caches directory and hydrate the view model before its first network/CLI refresh.
- Keep cached content visible while the panel refreshes in the background; expose a subtle refresh indicator and stale-load error banner.
- Move `SettingsView` into a separate SwiftUI `Settings` scene and open it through the macOS settings action.
- Translate every user-facing string and formatter result to Chinese.
- Remove all `Divider()` usage and preserve hierarchy with spacing and card backgrounds.
- Add cache round-trip/corruption tests plus view-model cache hydration and persistence tests.

Final commands:

```bash
xcodebuild -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' build
xcodebuild -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' test
git diff --check
```

## Risky boundaries and rollback points

- Treat the generated Xcode project as one checkpoint before feature code.
- Keep CLI mutation code isolated so it can be disabled without removing read-only profile and status display.
- Never verify by enabling, disabling, or changing the user's real autosubmit configuration unless explicitly authorized.
- If public API fields drift, adjust only transport mapping and fixtures; preserve stable display models.
