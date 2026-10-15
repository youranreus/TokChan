# Cursor Pre-submit Sync

## 1. Scope / Trigger

Use this contract when changing explicit upload orchestration, Cursor sync validation, or the `syncCursorBeforeSubmit` preference. This opt-in exception extends the original submit-only sequences in [Tokscale Integration](./tokscale-integration.md). Explicit Cursor sync can have a longer download budget than submit's implicit sync; preparing the cache first reduces stale-cache uploads but does not fix upstream scheduling or guarantee complete server freshness.

## 2. Signatures

```text
npx --yes tokscale@<configured-version> cursor sync --json
```

```swift
struct UserPreferences {
    var syncCursorBeforeSubmit: Bool // default false
}
protocol TokscaleCLIService {
    func syncCursor(context: TokscaleCommandContext) async throws
}
```

The JSON response contains required `synced: Bool`, required `rows: Int`, and optional `error: String?`. Unknown extra fields are allowed; missing error and JSON null both mean no error.

## 3. Contracts

- Persist the Boolean in `UserDefaultsPreferencesStore`, including its owned-key reset list. Preserve it in `DashboardViewModel.normalized(_:)`. Missing keys default to false; no dashboard cache schema change is needed.
- General Settings presents the immediate-save native toggle “提交前同步 Cursor” near Agent connection with accessibility identifier `sync-cursor-before-submit`. It is disabled during explicit operations. Explain that it affects only TokChan submissions/run-now, not Tokscale scheduled autosubmit, and that sync failure prevents upload. It is not an autosubmit draft field and needs no Apply.
- All three explicit upload entry points call the shared `prepareExplicitUpload`: onboarding `submitFirstUsage`, ordinary `submitUsageAndRefreshStatistics` (panel/menu, including an online menu action in local mode), and `runAutosubmitNow`. If enabled, run exactly one sync before the existing submit/run command, using the captured configured npx/version context. Never substitute global `tokscale` or add login/status probes.
- Require process success, decodable JSON, `rows >= 0`, `synced == true`, and `error == nil`. Zero rows is valid. An error with synced=true is a partial failure and must block. Exit code zero alone does not mean success; the upstream sync command can report failure inside JSON while exiting normally.
- Unknown/malformed responses throw `invalidCursorSyncResult`; negative rows also reject. False synced or any non-null string error throws `cursorSyncFailed`. Do not display raw JSON/account-bearing error text. At orchestration level present “Cursor 同步失败，未提交用量” with retry guidance; process/context failures retain bounded details through `CursorPreflightFailure`.
- Capture preferences and `uploadContextRevision` once per action. Increment revision on account/CLI-context changes, even changes away and back. Check cancellation before and after sync, then verify revision, account, and CLI-context before upload. Superseded results/errors must not upload, refresh, or publish into replacement context. Update every CLI implementation/fake explicitly; no default protocol no-op.
- Keep one existing submitting/running-autosubmit busy interval across preflight, upload, and follow-ups. Duplicate/conflicting explicit operations remain excluded. Popover closure suppresses eventual banners but does not cancel explicit work. A change to the toggle applies to the next action, not half a sequence.
- Sync failure performs zero upload and zero post-upload profile/status reads and does not advance display freshness. Successful uploads keep their existing complete-batch/status-read semantics. Reuse existing onboarding/submit diagnostics/Settings feedback surfaces.
- Default off preserves existing command counts. No explicit preflight sync in ticks, wake, app load, local graph refresh, remote refresh-only, login/status, pricing dry-run, autosubmit configure/disable, or externally scheduled autosubmit. Graph may independently sync upstream under its existing contract.
- Run-now performs sync unconditionally when enabled, even if upstream client filters exclude Cursor. This is an explicit TokChan policy, not scheduler configuration. No scheduler/file mutation, direct credential/cache reads, automatic retries, new sync button, or upstream timeout changes.
- Preserve the 300-second per-command process timeout. An unsupported older CLI or longer export fails safely. A concrete version pins the command selector; `latest` remains a moving alias. Submit can still attempt its own implicit sync and fall back to the cache just prepared.

## 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| No key / toggle off | Original upload sequence; zero explicit sync |
| Toggle changed | Persist/publish only; zero CLI/API/cache operations |
| synced=true, rows>=0, no error | Proceed to guarded upload |
| synced=false or any non-null error string | Block upload, report failure without raw account JSON |
| Missing/wrong required field, negative rows, empty or malformed stdout | Reject response; no upload/follow-ups |
| Missing npx, invalid version, nonzero exit, timeout | Retryable preflight failure; no upload |
| Cancellation or account/context revision changed during sync | Superseded; no upload or stale error publication |
| Popover closes during sync | Continue explicit sequence; preserve banner suppression |
| Configuration reset | Clear Boolean to false; retain upstream credentials/cache/scheduler |

## 5. Good / Base / Bad Cases

- Good: enabled normal action records `sync,submit,fetch`; run-now records sync then run then the existing profile/status reads.
- Base: upgraded installation has no new key and records the original `submit,fetch` sequence.
- Bad: treating successful process exit as successful sync, accepting a partial multi-account error, ignoring cancellation between commands, or implementing a second scheduler to cover external autosubmit.

## 6. Tests Required

- `CursorSyncCLITests`: exact versioned npx arguments; successful/zero-row/extra-field JSON; false synced, partial/empty-string error, malformed/empty/missing/type/negative data; process/context/timeout/cancellation failures.
- `PreSubmitCursorSyncTests`: enabled/disabled chains for all three upload entry points, local-mode online action, failure/cache preservation, duplicate/conflict exclusion, cancellation despite a fake ignoring it, account/context changes including away/back, popover closure, and zero sync for other paths.
- Preferences tests: default/missing-key false, round-trip, normalization retention, owned-key reset, and no effects from preference-only changes.
- Offline UI test: toggle persists without Apply and after reopening Settings, scope/failure explanation exists. A SystemUIServer-unavailable skip is an unverified UI gate, not proof of behavior.

## 7. Wrong vs Correct

Wrong:

```swift
_ = try await runner.run(executable: npx, arguments: syncArguments, timeout: timeout)
try await cli.submit(context: context) // process success is insufficient
```

Correct:

```swift
let response = try decoder.decode(CursorSyncResponse.self, from: Data(output.stdout.utf8))
guard response.rows >= 0 else { throw TokscaleCLIError.invalidCursorSyncResult }
guard response.synced, response.error == nil else { throw TokscaleCLIError.cursorSyncFailed }
// The caller still checks cancellation and captured account/context revision before upload.
```
