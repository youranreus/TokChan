# Implementation Plan

## Ordered checklist

1. Add `LaunchAtLoginStatus`, `LaunchAtLoginServicing`, and the live `SMAppService.mainApp` adapter under `TokChan/Shared/Services`.
2. Add a focused `@MainActor` settings model that derives toggle/supporting UI state, performs immediate register/unregister actions, reconciles status after every attempt, and exposes recovery errors.
3. Inject the live service from `TokChanApp`; provide deterministic non-system behavior for the existing `--ui-testing` path.
4. Add a native “启动” section to the General settings tab with:
   - “登录时启动 TokChan” Toggle;
   - operation disabling/progress feedback;
   - enabled, approval-required, and unavailable status text;
   - an “打开系统设置” recovery action for approval-required state.
5. Refresh login-item status when Settings appears and when the app scene returns to active, without changing the existing Save/dismiss behavior for other settings.
6. Add fake-backed unit tests covering status mapping, refresh, immediate registration/unregistration, post-action reconciliation, failures, and approval-required recovery.
7. Run focused and full validation, inspect the diff against macOS specs, then manually validate with a signed app build.

## Automated validation

```bash
xcodebuild test -scheme TokChan -destination 'platform=macOS' -only-testing:TokChanTests/LaunchAtLoginSettingsModelTests
xcodebuild test -scheme TokChan -destination 'platform=macOS'
git diff --check
```

Also verify the project still compiles with `MACOSX_DEPLOYMENT_TARGET = 13.0` and that no helper target, LaunchAgent plist, entitlement, third-party package, or login-state `UserDefaults` key was introduced.

## Manual validation

1. Run a normally signed TokChan app from its intended installation location.
2. Open Settings > General and confirm the launch-at-login control uses native macOS styling and is independent of the page Save button.
3. Turn it on and verify TokChan appears under System Settings > General > Login Items.
4. If macOS reports approval required, verify the pending state is explicit and the button opens the correct System Settings panel.
5. Change approval/enablement in System Settings, return to TokChan, and confirm the UI refreshes to the real system state.
6. Turn the control off and verify the login item is removed/disabled.
7. Enable it, sign out and back in (or restart in a suitable test environment), and confirm TokChan returns as a menu-bar item without opening an ordinary app window.
8. Clean up the test login item if manual validation does not leave the feature enabled intentionally.

## Review gates before task start

- User approves the final PRD/design/implementation summary.
- `implement.jsonl` and `check.jsonl` each contain real macOS spec and research context entries.
- No unresolved product or scope questions remain.

## Risky files and rollback points

- `TokChan/TokChanApp.swift`: dependency wiring and UI-test isolation; revert together with the service injection.
- `TokChan/Features/Settings/SettingsView.swift`: preserve existing tab drafts, Save behavior, and successful-save dismissal.
- New ServiceManagement adapter: never invoke it from automated tests.
- Before manual validation, record current Login Items state; unregister the development build if rolling back.
- There is no persistence migration, so source rollback does not require data conversion.
