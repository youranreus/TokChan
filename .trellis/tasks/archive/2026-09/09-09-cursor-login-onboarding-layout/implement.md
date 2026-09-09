# Implementation Plan

## 1. Lock Cursor status command and parser behavior

- Add the read-only Cursor status command to the command builder and CLI service protocol.
- Implement the client method through the existing process runner; do not add shell execution or credential reads.
- Add a focused ANSI-safe parser that distinguishes valid, explicitly unavailable, and indeterminate output.
- Extend every fake and preview service with deterministic status behavior.
- Cover exact argument order, valid/no-account/expired markers, ANSI text, connectivity/HTTP/format text, empty/unknown output, non-zero exit, timeout, invalid version, and missing npx.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -only-testing:TokChanTests/CursorLoginCLITests
```

Rollback point: command/protocol/parser additions only.

## 2. Add settings-scoped Cursor connection lifecycle

- Add the non-persisted settings connection projection and a cancellable/request-identified refresh task.
- Trigger exactly one Cursor status check from each hidden-to-visible Settings transition, alongside but independent from autosubmit status.
- Reject stale results after Settings closes or the persisted npx/version context changes; schedule a fresh check for a changed context while visible.
- Add retry behavior for indeterminate failures.
- Ensure check progress prevents concurrent explicit Cursor/login mutations without turning the check into a dashboard success/failure banner.
- On login success, immediately project logged-in state while preserving the current-presentation success feedback.
- On Settings close, cancel/invalidate status work and clear transient login success/failure feedback; reopening must query again.
- Add event-count and race tests for continuous visibility deduplication, reopen, retry, login success, close/reopen, stale context, and zero sync/submit/fetch/mutation follow-ups.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -only-testing:TokChanTests/DashboardViewModelTests -only-testing:TokChanTests/OperationBannerLifecycleTests
```

Rollback point: connection state and lifecycle orchestration before UI rendering.

## 3. Render conditional Settings states

- Adapt the shared Cursor content or Settings wrapper so checking, logged-in, needs-login, and check-failed states have explicit UI.
- Parameterize the title so Settings shows “Cursor 登录” while onboarding retains “Cursor 登录（可选）”.
- Put the logged-in indicator in the header's trailing action slot formerly occupied by “自动登录”; do not render duplicate connected feedback below.
- Hide automatic login for checking, logged-in, and check-failed states.
- Show “重新检查” only for check failure, and show automatic login only after explicit unavailable classification.
- Preserve the onboarding Cursor module's optional explicit-login behavior independently.
- Preserve existing identifiers and add or retain identifiers for check progress, connected status, check failure, and retry.
- Add offline rendering/action tests; no UI test may invoke real npx or network access.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -only-testing:TokChanTests/SettingsWindowActionTests -only-testing:TokChanTests/DashboardLayoutTests
```

Rollback point: Settings presentation changes only.

## 4. Normalize onboarding account-control layout

- Define one shared account-control height for the rounded username field and both large buttons.
- Give the two button labels equal flexible widths and equal heights, preserving primary/secondary styling and default action.
- Remove asymmetric outer-frame expansion that currently leaves the secondary button at intrinsic width.
- Preserve disabled states, help text, submission behavior, and accessibility identifiers.
- Render the real onboarding card at 380×680 in normal, feedback, and busy states, in light and dark appearances; verify no clipping or unexpected gap.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -only-testing:TokChanTests/DashboardLayoutTests
```

Rollback point: onboarding view layout only.

## 5. Full quality and contract pass

- Run the Trellis quality check against the final diff and all acceptance criteria.
- Run the complete macOS test suite and whitespace validation.
- Update the Tokscale integration and SwiftUI/testing specs with the status command, failure semantics, Settings lifecycle, and equal-control layout contract.
- Confirm README wording remains accurate; update only if visible behavior makes it stale.
- Build and launch a fresh Debug app for manual experience after automated checks.

Validation commands:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS'
xcodebuild -project TokChan.xcodeproj -scheme TokChan -configuration Debug -destination 'platform=macOS' build
git diff --check
git status --short
```

## Risk Notes

- Tokscale Cursor status is human-readable and returns success for some unavailable states; parser fixtures must be narrow so connection/format failures do not accidentally expose automatic login.
- Adding a protocol requirement affects all test doubles and previews; compile failures should identify missed conformances.
- SwiftUI `.task`, `.onAppear`, and scene activation overlap; lifecycle tests must assert one query per continuous visible period.
- Closing Settings can race a status query or login completion; request identity and presentation cleanup must prevent stale success/status from reappearing.
- The onboarding viewport is fixed; visual equality must not increase total card height enough to clip lower content.
