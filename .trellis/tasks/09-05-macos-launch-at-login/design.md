# Technical Design

## Architecture and boundaries

Use Apple's `ServiceManagement` framework through a narrow app-owned boundary:

- `TokChan/Shared/Services/LaunchAtLoginService.swift`
  - `LaunchAtLoginStatus`: app-owned equivalents of enabled, not registered, approval required, and unavailable/not found.
  - `LaunchAtLoginServicing`: reads current status, registers, unregisters, and opens the Login Items system-settings panel.
  - `SystemLaunchAtLoginService`: adapts `SMAppService.mainApp` and `SMAppService.openSystemSettingsLoginItems()`.
- `TokChan/Features/Settings/LaunchAtLoginSettingsModel.swift`
  - A focused `@MainActor ObservableObject` owns UI-facing status, operation state, and recoverable error text.
  - It performs immediate enable/disable operations and always re-reads the system status after success or failure.
- `TokChan/Features/Settings/SettingsView.swift`
  - Adds a native Toggle and status/recovery content to a new “启动” section in the existing General tab.
  - Observes app activation and asks the model to refresh, so changes made in System Settings are reflected.
- `TokChan/TokChanApp.swift`
  - Constructs the live service and injects it into Settings. UI-test mode injects a deterministic fake/no-op implementation so tests never alter the host machine.

This keeps ServiceManagement calls out of SwiftUI rendering and out of the unrelated `DashboardViewModel`.

## State contract

The model exposes one authoritative state derived from the service:

| App state | Toggle | Supporting UI |
|---|---:|---|
| enabled | on | “已启用” confirmation |
| not registered | off | no warning |
| requires approval | on | Orange pending-approval explanation plus “打开系统设置” action |
| unavailable/not found | off and disabled | Plain-language unavailable message |

`requiresApproval` renders the toggle on because registration was requested and remains installed, but clearly states that automatic launch is not effective until the user approves it. Turning that toggle off unregisters the pending item.

The model also exposes `isUpdating` and `errorMessage`:

- Disable the toggle while one register/unregister call is running, preventing duplicate operations.
- Clear stale operation errors when a new attempt starts.
- On completion, re-read status rather than trusting the requested Boolean.
- On thrown errors, retain a plain-language error message and still restore the UI from the system's real status.

The login-item state is never stored in `UserDefaults`.

## Interaction and data flow

1. Settings appears and calls `refresh()` alongside the existing dashboard/settings load.
2. User changes the launch-at-login Toggle.
3. The Toggle calls `setEnabled(_:)` immediately; the existing page “保存” action is not involved.
4. The model invokes `register()` or `unregister()` on the injected service.
5. The model reads `status` again and updates published state; any error is shown within the launch section.
6. If status is approval-required, the user can invoke the service's system-settings action.
7. When `scenePhase` becomes active after visiting System Settings, the view refreshes status again.

Existing username, npx, and autosubmit drafts continue to use the current Save flow without changes.

## Compatibility and packaging

- `SMAppService` is available on macOS 13, matching the project's deployment target; no availability fallback or legacy API is needed.
- Register the main app with `SMAppService.mainApp`; do not add a helper app, launch plist, login-item bundle, entitlement, or third-party dependency.
- The existing non-sandboxed configuration remains unchanged. ServiceManagement still owns registration and user approval.
- The file-system-synchronized Xcode groups include new Swift files automatically, so no manual project source entries should be necessary.

## Testing strategy

Use a fake `LaunchAtLoginServicing` that records calls, exposes controllable statuses, and can throw deterministic errors. Unit-test the model for:

- all four status-to-toggle/UI mappings;
- refresh behavior;
- immediate register and unregister calls;
- post-operation status reconciliation;
- register and unregister failures;
- pending approval and opening System Settings;
- prevention of real ServiceManagement mutations in UI-test mode.

Do not call `SMAppService.mainApp.register()` or `unregister()` from automated tests. Run the full Xcode suite, then manually validate the signed application in System Settings and across a user login/restart boundary.

## Risks and mitigations

- **External state changes:** refresh on appearance and active scene transitions.
- **Approval is not programmable:** distinguish pending approval from enabled and provide the system-settings shortcut.
- **Misleading optimistic UI:** reconcile from `SMAppService.status` after every attempt.
- **Test machine pollution:** keep the live API behind injection and use fakes in tests/UI-test launch mode.
- **App placement/signing differences:** include a manual validation gate using a normally signed app in its intended installation location.

## Rollback

The feature has no persisted-data migration. Rollback consists of removing the launch-at-login service/model/tests and the Settings/TokChanApp wiring. If a development build was registered during manual validation, unregister it through the app or System Settings before rollback.
