# macOS Service Management

## Scenario: Main app launch at login

### 1. Scope / Trigger

Use this contract whenever TokChan exposes or changes user-controlled launch-at-login behavior. TokChan targets macOS 13+, so the main app must use `ServiceManagement.SMAppService.mainApp`; do not add a helper app, write a LaunchAgent plist, call deprecated `SMLoginItemSetEnabled`, or persist a duplicate enabled flag.

### 2. Signatures

Keep ServiceManagement behind a main-actor-isolated integration boundary:

```swift
enum LaunchAtLoginStatus: Equatable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
}

@MainActor
protocol LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}
```

The live adapter maps `SMAppService.mainApp.status`, calls `register()` / `unregister()`, and uses `SMAppService.openSystemSettingsLoginItems()` for user approval recovery.

### 3. Contracts

- System status is the only source of truth; never mirror launch-at-login enablement in `UserDefaults`.
- A settings toggle applies immediately and remains independent from unrelated draft-setting Save actions.
- Re-read status after every register/unregister attempt, including thrown errors. An API call may throw while the authoritative status has already become `requiresApproval`.
- Refresh when Settings appears and whenever the app becomes active after the user may have changed Login Items externally.
- Treat `requiresApproval` as registered/requested (toggle on) but not yet effective; explain that user action is required and provide the system-settings action.
- Treat `notFound` as unavailable (toggle off and disabled), not as a successful unregister.
- A release app must carry a complete Bundle signature whose designated identifier matches `CFBundleIdentifier`, with Info.plist and resources sealed. A linker-generated ad-hoc Mach-O signature is insufficient and can make `SMAppService.mainApp.status` return `notFound`; follow `release-workflow.md` and require strict `codesign` verification.
- The UI-test launch path must use an in-memory fake only in `DEBUG`; Release builds must ignore `--ui-testing` and always construct the system adapter.
- Automated tests must never register the test runner or mutate the host Mac's Login Items.

### 4. Validation & Error Matrix

| System result | UI state | Error behavior |
|---|---|---|
| `.enabled` | Toggle on; eligible-to-run confirmation | Clear stale operation error |
| `.notRegistered` | Toggle off | Clear stale error on explicit refresh |
| `.requiresApproval` | Toggle on; pending warning and Login Items button | Do not show a contradictory registration failure if this is the post-call status |
| `.notFound` / unknown future status | Toggle off and disabled; unavailable explanation | Do not claim registration or unregistration succeeded |
| Installed `/Applications` app remains `.notFound` | Inspect full Bundle signature, designated identifier, Info.plist binding, and sealed resources | Do not diagnose location alone when `codesign --verify --deep --strict` fails |
| `register()` throws and status stays off/unavailable | Reconcile to system status | Show plain-language enable failure with technical localized detail |
| `unregister()` throws and status stays on/pending | Reconcile to system status | Show plain-language disable failure with technical localized detail |

### 5. Good / Base / Bad Cases

- **Good:** Register changes status to `requiresApproval`; the toggle remains on, approval guidance appears, and no contradictory error is shown.
- **Base:** Status is `notRegistered`; the toggle is off and a user toggle immediately calls `register()`.
- **Bad:** Store `true` in `UserDefaults` before registration and render it as enabled even though System Settings rejected or disabled the item.
- **Bad:** Let Release honor a command-line UI-testing marker and silently substitute fake registration state.

### 6. Tests Required

Fake-backed unit tests must assert:

- all four `SMAppService.Status` mappings;
- enabled/available derivation for every app status;
- immediate register and unregister call counts;
- post-operation reconciliation from the fake's authoritative status;
- register/unregister failure messages only when final status does not satisfy the request;
- stale errors clear after external refresh;
- pending approval can open Login Items and other states cannot;
- UI-test factory behavior is in-memory under Debug.

Run the full macOS Xcode suite and a Release build. Manual signed-app verification must cover Login Items visibility/removal, approval, external changes, and actual launch after sign-out/restart.
For release workflow changes, extract the final ZIP and assert strict Bundle verification, `Identifier=com.youranreus.TokChan`, Info.plist coverage, sealed resources, and both architectures before testing the installed app.

### 7. Wrong vs Correct

#### Wrong

```swift
@AppStorage("launchAtLogin") var launchAtLogin = false

func enable() {
    launchAtLogin = true
    try? SMAppService.mainApp.register()
}
```

This hides errors and lets application state drift from the system-owned registration/approval state.

#### Correct

```swift
func setEnabled(_ enabled: Bool) {
    var operationError: Error?
    do {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    } catch {
        operationError = error
    }

    status = service.status
    if let operationError, !statusMatchesRequest(enabled) {
        errorMessage = operationError.localizedDescription
    }
}
```

The system remains authoritative even when ServiceManagement reports a recoverable error.
