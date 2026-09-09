# Technical Design

## Overview

The change keeps `DashboardViewModel` as the orchestration boundary, extends the existing Tokscale CLI adapter with one fixed Cursor login command, and projects the same login state into onboarding and General Settings. No new persistence or credential boundary is introduced.

## State Model

### First-use identity

- Change the empty-username initial projection from `.discoveringIdentity` to `.usernameEntry(message: nil)`.
- `load()` must not call `whoAmI` when the username is empty. It may retain the existing independent autosubmit-status read so this change does not broaden into scheduler/status behavior.
- Add `discoverIdentity()` as the sole user-triggered path into `.discoveringIdentity`.
- On discovery success, route the normalized username through the existing preference-update and complete-batch verification flow rather than duplicating cache invalidation rules.
- On context/discovery failure, return to `.usernameEntry(message:)` without changing saved preferences.
- Preserve generation/account checks so a Settings edit that wins during suspended discovery remains authoritative.

### Cursor login

Introduce a dedicated published projection such as:

```swift
enum CursorLoginState: Equatable {
    case idle
    case loggingIn
    case succeeded(String)
    case failed(message: String, fallbackCommand: String)
}
```

`DashboardViewModel.loginCursor()` will:

1. Reject duplicate or conflicting explicit operations.
2. Resolve the current persisted command context.
3. Mark Cursor login and the shared operation-busy projection as running.
4. Execute exactly one Cursor login command.
5. Publish success without sync/fetch/status work, or publish failure with the terminal fallback command.

Cursor login participates in the same explicit-operation exclusion used by submit/autosubmit operations so another CLI mutation cannot start concurrently. The dedicated state lets both screens render precise feedback without mistaking unrelated operation results for Cursor login.

## CLI Boundary

Extend `TokscaleCommand` with `.cursorLogin`, producing this discrete argument array:

```text
["--yes", "tokscale@<validated-version>", "cursor", "login"]
```

Extend `TokscaleCLIService` with `loginCursor(context:)`. `TokscaleCLIClient` delegates to the existing runner, preserving:

- semantic version validation
- resolved executable URL
- child PATH repair
- timeout and cancellation
- non-zero exit sanitization/truncation
- no shell invocation

The user-copyable fallback is presentation text, not an executable command. It uses `npx tokscale@<validated-version> cursor login` and is copied via `NSPasteboard`; TokChan never executes that string through a shell.

## UI Composition

### Onboarding

- Keep the existing two-step indicator.
- In the step-one username card, add a secondary “识别本机登录” button near manual username entry.
- Add a compact optional Cursor card/module below the account controls, explicitly labeled optional.
- Show inline progress/success/failure. Failure includes a selectable/copyable terminal command.
- Bound feedback height and wrapping so the 380×680 popover remains usable.

### Settings

- Add a “Agent 连接” (or equivalent) section to General Settings containing the Cursor login action and the shared state feedback.
- Keep normal preference persistence immediate; no shared Save button is added.
- Disable conflicting controls while a CLI operation is running.

Where practical, extract a small reusable Cursor login content view so command copy, accessibility identifiers, and feedback wording cannot drift, while allowing onboarding and Form containers to own their layout.

## Data Flow

```text
User click
  -> DashboardViewModel.loginCursor()
  -> commandContext(saved preferences)
  -> TokscaleCLIService.loginCursor(context)
  -> TokscaleCommandBuilder(.cursorLogin)
  -> existing ProcessRunning boundary
  -> CursorLoginState
  -> onboarding + settings projections
```

No token, cookie, account label, login-complete flag, or Cursor cache content enters TokChan persistence.

## Compatibility and Races

- Existing configured users bypass onboarding exactly as before.
- Empty-username background statistics remain silent; only the explicit button may invoke `whoami`.
- If username/preferences change during identity discovery, the latest saved account/context wins and stale discovery must not overwrite it.
- Cursor login captures one validated context. Later preference edits do not alter the running child; its result may be shown as the result of that explicit attempt but must not trigger follow-up work under the new context.
- Fake/preview CLI implementations must add deterministic `loginCursor` behavior.

## Error Handling

- Invalid version or missing npx fails before process launch and shows the existing localized error plus fallback guidance when applicable.
- CLI non-zero and timeout reuse existing error mapping.
- Since interactive token input is out of scope, every unsuccessful in-app login offers the copyable terminal command; no prompt parsing or pseudo-terminal is introduced.

## Rollback

The change is additive at the CLI boundary and state projection. Rollback consists of removing `.cursorLogin`/`loginCursor`, the dedicated state/UI module, and restoring automatic discovery in `load()`. No data migration is needed.
