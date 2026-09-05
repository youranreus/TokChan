# macOS Launch at Login Research

## Recommendation

Use `ServiceManagement.SMAppService.mainApp` directly. The project targets macOS 13, exactly the first release where Apple designates `SMAppService` as the API for registering and controlling login items. Do not add a helper target, persist a second enabled flag, write a LaunchAgent plist, or use legacy `SMLoginItemSetEnabled`.

## Authoritative Apple API findings

Sources:

- [`SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)
- [`SMAppService.register()`](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
- [`SMAppService.unregister()`](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister())
- [`SMAppService.status`](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.property)
- [`SMAppService.Status`](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum)
- [`SMAppService.openSystemSettingsLoginItems()`](https://developer.apple.com/documentation/servicemanagement/smappservice/opensystemsettingsloginitems())

Apple's documentation states:

- In macOS 13 and later, `SMAppService` registers and controls login items, launch agents, and launch daemons.
- `mainApp` represents the main application as a login item.
- `register()` registers the service so it can launch, subject to user approval.
- `unregister()` removes registration so the system no longer launches it.
- `status` is the registration/authorization source of truth.
- `openSystemSettingsLoginItems()` opens the system Login Items panel.

`SMAppService.Status` meanings:

| Status | Apple meaning | Product mapping |
|---|---|---|
| `.enabled` | Successfully registered and eligible to run | Toggle on; enabled confirmation |
| `.notRegistered` | Not registered (or attempted re-registration after already registered) | Toggle off |
| `.requiresApproval` | Registered, but the user must act in System Settings | Toggle on as requested/registered, with a prominent pending-approval message and button to open Login Items |
| `.notFound` | Framework could not find the service | Toggle off/unavailable, with an error/status message rather than claiming success |

The system owns approval and can be changed outside the app, so UI state must be refreshed from `status` when settings appears and when the app becomes active. A separate `UserDefaults` Boolean would drift from the real system state.

## Repository findings

- Deployment target is macOS 13 (`TokChan.xcodeproj/project.pbxproj`, `MACOSX_DEPLOYMENT_TARGET = 13.0`), so no legacy compatibility path is required.
- The app is a SwiftUI menu-bar app with `MenuBarExtra` and a native `Settings` scene (`TokChan/TokChanApp.swift`). Launching the main app at login naturally restores its menu-bar presence; no helper executable is needed.
- The current settings implementation has native tabs and places application-level controls under General (`TokChan/Features/Settings/SettingsView.swift`). The new control should live there rather than add another tab.
- Existing mutable settings use local drafts and a shared Save button. A system login-item registration is different: it is an external authorization/registration operation with its own errors and possible pending-approval state.
- Project guidance requires local state, a real injectable boundary for testable system behavior, main-actor UI mutation, plain-language recoverable errors, and no dependency when Apple frameworks suffice (`.trellis/spec/macos/state-management.md`, `quality-guidelines.md`, `testing-guidelines.md`).
- The Xcode project uses file-system-synchronized groups, so new Swift source/test files do not need manual PBX file entries.

## Proposed architecture

- Add a small protocol-backed launch-at-login service under `TokChan/Shared/Services`, implemented with `SMAppService.mainApp`.
- Expose an app-owned status enum rather than leaking ServiceManagement types into view code.
- Add a focused `@MainActor` observable settings model (or equivalent narrowly scoped state owner) that refreshes status, performs register/unregister, guards concurrent operations, and refreshes from the system after every attempt.
- Inject the live implementation from `TokChanApp`; inject a fake in unit tests and UI-testing setup.
- Treat `.requiresApproval` as registered-but-not-yet-effective and provide `SMAppService.openSystemSettingsLoginItems()`.
- Refresh on settings appearance and `scenePhase == .active` so external System Settings changes are reflected.

## Testing and distribution constraints

- Unit tests must use a fake service; they must never register the test runner or mutate the developer machine's Login Items.
- Build/tests can verify abstraction behavior and UI-facing state mapping, but a signed app installed/launched from a normal application location should be manually checked for actual Login Items visibility and login launch behavior.
- Manual validation should cover register, unregister, approval-required flow, changing the item in System Settings, relaunching Settings, and ensuring only one TokChan login-item entry exists.

## Product decision

The user approved immediate application: toggling registers or unregisters independently of the existing Save button. This matches the system-owned authorization flow and keeps failures separate from unrelated settings drafts.
