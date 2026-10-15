# Design: optional Cursor sync before explicit uploads

## Boundaries and data flow

Keep the policy in DashboardViewModel, the process/JSON contract in TokscaleCLIClient, and the durable user choice in UserPreferences/UserDefaultsPreferencesStore. No new dependency, scheduler, raw Cursor file access, or direct HTTP API is introduced.

Add `syncCursorBeforeSubmit: Bool = false` to UserPreferences, its initializer, defaults, load/save/clear key list, and DashboardViewModel.normalized. General Settings adds a native immediate-save toggle named “提交前同步 Cursor” near Agent connection, with a stable accessibility identifier `sync-cursor-before-submit`. Explanation: “仅影响 TokChan 发起的提交和立即运行自动提交，不影响 Tokscale 定时自动提交。同步失败时不会提交。” Disable the control during a running explicit operation. This is not part of AutosubmitSettingsDraft or its Apply lifecycle.

Add `TokscaleCommand.cursorSync` with suffix `["cursor", "sync", "--json"]` and `TokscaleCLIService.syncCursor(context:) async throws`. Implementations must explicitly supply the method, including previews/UI fixtures and test doubles; do not add a default protocol no-op that could silently bypass the requirement.

The service runs through the existing npx process runner and requires a zero process exit, then decodes a typed stdout response:
- `synced`: required Boolean, must be true.
- `rows`: required nonnegative integer; zero is legitimate success.
- `error`: optional string; must be absent or null. Any non-null error, including a partial multi-account warning, blocks the upload.
- Unknown extra JSON fields are allowed. Empty, malformed, wrong-type, or missing required data fails closed.

Use dedicated localized invalid-sync-result / sync-failed errors with clear “Cursor 同步失败，未提交用量” wording. Do not expose raw credential contents or entire JSON responses; keep process diagnostics bounded under existing error handling. Preserve existing missing-npx, invalid-version, nonzero-exit, and timed-out failures, contextualized as preflight failure at presentation. Do not run cursor status/login as prerequisites: status is a different endpoint and does not establish download success.

## Explicit-operation sequence

All three upload entry points participate:
1. `submitFirstUsage()` (onboarding).
2. `submitUsageAndRefreshStatistics()` (status menu and online panel refresh).
3. `runAutosubmitNow()` (Settings).

A small shared private preflight helper receives the captured npx/version context, account and flag. Keep orchestration in the view model so account/context changes can stop a pending upload. Maintain the existing `.submitting` / `.runningAutosubmit` busy state across preflight and upload; do not create a separate operation lifetime or reset panel presentation generations between stages.

Sequence:
1. Acquire existing explicit-operation exclusion and capture account, configured context, and flag.
2. If enabled, await exactly one `syncCursor(context:)`.
3. Before issuing the upload, check task cancellation and verify the captured account and CLI context still match. Superseded work does not upload, fetch, or publish an old error into the replacement context. This guard also applies to onboarding.
4. Invoke the existing submit or run-now command with that same context.
5. Retain existing post-upload account/context guards, profile refresh, autosubmit-status reads, and first-use behavior. Preflight failure performs none of these follow-ups, keeps existing display cache/freshness, and uses the appropriate existing action error surface (onboarding message, submit diagnostics/banner, or Settings operation feedback).

Capture the flag once. A settings update affects the next action, never half of a running sequence. Closing the dashboard popover does not cancel explicit work; use existing banner-generation suppression. Duplicate actions and competing Cursor login/status/configuration remain excluded. Do not broaden the existing global coordination boundary to unrelated custom-pricing operations in this task.

## Compatibility and limitations

The default-off setting preserves current command sequences and upgrades with no key default to false. Reset clears the owned Boolean; do not bump dashboard snapshot schema. Unsupported older CLIs fail clearly when enabled; never fall back to an unchecked plain-text sync or silently skip preflight.

The configured version selector is reused for both commands. A concrete version pins both; `latest` remains the existing user-selected moving alias, so do not claim immutable resolution across commands or add package pinning machinery here.

Retain the existing 300-second per-command process timeout. Longer latest-version exports can exceed it and then block upload safely; configurable/extended sync budgets are deferred. No new automatic retry is added. Submit may still attempt its own 15-second implicit sync and fall back to the freshly prepared cache. This does not bypass upstream sync, guarantee complete server visibility, or prevent another external CLI process from replacing its cache.

Even if the upstream autosubmit filter excludes Cursor, the enabled TokChan setting performs the preflight unconditionally for run-now: the switch is explicit policy, not a second parser of upstream scheduler configuration. Missing Cursor setup therefore blocks while enabled; users without Cursor leave it off.

## Rollout / rollback

Ship disabled by default. Turning off the switch immediately restores the original command chain for future actions. A code rollback leaves an unused Boolean key, with no upstream scheduler or usage migration to undo. Update the integration/persistence/testing specs together with implementation after checks, documenting the opt-in exception to previous exact-submit-only sequences and keeping login/read-only invariants intact.
