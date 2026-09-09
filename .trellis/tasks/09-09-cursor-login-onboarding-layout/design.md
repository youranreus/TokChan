# Technical Design

## Overview

Extend the existing Tokscale CLI adapter with a read-only Cursor status command and project its result into a settings-specific connection state. Reuse the existing settings visibility boundary to query once per opening and clear transient login feedback on close. Keep onboarding's optional login behavior independent, while adjusting only its account-control sizing and distribution.

## CLI and Parsing Boundary

Add `TokscaleCommand.cursorStatus`, producing the discrete argument array:

```text
["--yes", "tokscale@<validated-version>", "cursor", "status"]
```

Extend `TokscaleCLIService` with a status-reading method returning a semantic result rather than exposing raw process output to the view model. `TokscaleCLIClient` runs the command through the existing executable URL, PATH repair, timeout, cancellation, bounded output, and no-shell boundary.

Introduce a focused parser/result such as:

```swift
enum CursorSessionStatus: Equatable {
    case valid
    case unavailable
    case indeterminate
}
```

The parser strips ANSI escapes and classifies only the researched stable markers. `Session: Valid` is valid; `No saved Cursor accounts.` and the explicit `Session token expired or invalid` marker are unavailable. Connectivity, HTTP, parse/format, empty, and unknown output are indeterminate. Context/process failures remain thrown errors and are also presented as an indeterminate check failure. No raw account/token data is persisted.

## ViewModel State

Keep `CursorLoginState` for explicit login progress and transient success/failure feedback. Add a settings connection projection such as:

```swift
enum CursorConnectionState: Equatable {
    case idle
    case checking
    case loggedIn
    case needsLogin
    case checkFailed(String)
}
```

The state is intentionally not persisted. Settings rendering rules are:

- idle/checking: no login button; checking feedback is visible.
- loggedIn: show a green “已登录” status; hide automatic login.
- needsLogin: show automatic login.
- checkFailed: show failure text plus “重新检查”; hide automatic login.

`loginCursor()` retains its existing explicit-operation exclusion. On success it sets the connection projection to `.loggedIn` immediately and keeps the short success feedback for the current presentation. Failure retains the existing fallback command and leaves/reprojects the setting as needing login so the user can retry.

## Settings Lifecycle and Concurrency

`settingsDidBecomeVisible()` remains the single deduplicating boundary for `.task`, `.onAppear`, and active-scene callbacks. On a hidden-to-visible transition it schedules both existing autosubmit status refresh and one Cursor status refresh. Repeated visible callbacks start neither a second Cursor check nor a duplicate autosubmit read.

Use a dedicated cancellable task/request identity for Cursor status so a late result from an earlier presentation or changed npx/version context cannot overwrite the current projection. A status check is read-only and may coexist with the independent autosubmit status read, but its local checking flag disables Cursor login/retry and contributes to the user-operation busy projection so explicit mutations cannot start concurrently.

`settingsDidBecomeHidden()`:

- marks Settings hidden;
- invalidates/cancels the current Cursor status presentation request;
- resets settings connection projection to idle;
- clears transient `CursorLoginState.succeeded` (and other presentation feedback where appropriate) so reopening never displays the old success banner.

A new opening always starts a fresh query. If npx/version changes while Settings remains visible, invalidate the old result and schedule one check for the new command context, mirroring existing stale-context protection.

## UI Composition

### Settings

Adapt `CursorLoginView` with presentation inputs or split a small shared content component from a settings wrapper. The shared row accepts context-specific title and trailing content: Settings uses “Cursor 登录”; its checking spinner and connected status occupy the same trailing slot used by automatic login, while onboarding retains “Cursor 登录（可选）”. Settings owns status-check states and retry action; onboarding continues to own only explicit login states. This prevents a settings status check from hiding or blocking the optional onboarding module.

Do not render a second connected-status row below the shared header. Preserve existing accessibility identifiers and add or retain stable identifiers for checking, connected, check failure, and retry states needed by tests.

### Onboarding account controls

Use one shared control height for the rounded username field and both `.large` buttons. Lay out the two buttons in equal flexible columns so each receives half of the available row width, with the same height and existing spacing. Apply the width to each button's label/content shape rather than only expanding one outer button frame, avoiding the current asymmetric intrinsic-size gap.

Retain “继续” as bordered prominent/default action and “识别本机登录” as secondary. Preserve disabled conditions, help copy, submit behavior, and accessibility identifiers. Validate the real card in the fixed 380×680 viewport for idle, feedback, and busy states in light/dark appearances.

## Compatibility and Failure Semantics

- Status query failure never proves a session is unavailable. It shows retry-only and does not expose automatic login.
- Older Tokscale versions that lack `cursor status`, missing npx, timeout, non-zero exit, or unknown output all use retry-only failure.
- Explicitly recognized no-account/invalid-session output is the only path that offers automatic login.
- No new persistence or migration is required.
- No sync, submit, profile fetch, or autosubmit mutation follows a status check or successful login.

## Rollback

The status feature is additive: remove the command/protocol/parser, connection state/task, and settings conditional rendering to return to the existing always-visible login action. The onboarding layout can be reverted independently. There is no stored data to migrate or roll back.
