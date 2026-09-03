# Implementation Plan

1. Update `SettingsView` with a typed tab selection and native `TabView` / `.tabItem` Preferences Toolbar navigation.
2. Move existing general and autosubmit controls into tab-specific private views without changing bindings or validation behavior.
3. Add the final About tab with bundle version and basic TokChan/Tokscale information.
4. Remove the self-drawn close, cancel, title, and tab controls while preserving successful-save dismissal, error feedback, and npx selection.
5. Use the native `openSettings` environment action on macOS 14+, retain responder-chain compatibility for macOS 13, and activate the app before opening settings.
6. Add focused source-level or view tests only if the existing test structure can verify stable behavior without brittle SwiftUI internals.
7. Run `xcodebuild test -scheme TokChan -destination 'platform=macOS'` and inspect the diff for scope and accessibility issues.

Validation:

- `xcodebuild test -scheme TokChan -destination 'platform=macOS'`
- Confirm the project still builds on macOS 13 APIs.
- Review `SettingsView` for tab order, default tab, native window close behavior, and preservation of local draft state.
- Confirm the native Preferences Toolbar appearance in the running app.

Result:

- Implemented with SwiftUI `Settings` + `TabView` + SF Symbol `.tabItem` labels; AppKit toolbar bridging was not required.
- User confirmed the resulting toolbar appearance matches the requested native macOS Preferences style.
- Full verification passed: 26 unit tests, 1 UI test, and `git diff --check`.

Rollback points:

- Before code changes: only planning artifacts exist.
- After implementation: revert the settings view, settings entry changes, and focused test together; no persistence migration or project-file rollback is needed.
