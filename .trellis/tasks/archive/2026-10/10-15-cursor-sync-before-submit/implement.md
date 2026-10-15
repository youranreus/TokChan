# Implementation plan

Status: implementation and feature commit approved; committed as `b2678b7`. Independent review, 298 unit tests and unsigned Release builds passed. Five automated UI tests remain skipped due to SystemUIServer visibility; the user subsequently accepted the local signed Debug build with “没问题，继续后续流程，记得记录fragment”. Manual acceptance is complete. Release fragment and closeout bookkeeping are being prepared; see verification.md.

## Ordered checklist

1. Load macOS specs with trellis-before-dev. Re-read this PRD/design/research and inspect actual current tests/doubles. Baseline the focused Xcode test suite; report environmental failures separately.
2. Add deterministic command-builder and fake-runner tests for `cursor sync --json`: successful JSON, zero rows, unknown extra fields, synced=false, non-null error with synced=true, missing required fields, invalid types/negative rows, malformed/empty stdout, nonzero process exit, and thrown timeout/cancellation. Use a test file such as `CursorSyncCLITests.swift`, explicitly registered in the Xcode test target if required.
3. Implement the validated CLI method and typed errors. Update every live/preview/UI-test/fake implementation of TokscaleCLIService explicitly. Keep ordinary submit/run methods unchanged and no silent protocol-extension fallback.
4. Add `syncCursorBeforeSubmit` with default false through preference initializer/load/save/clear and view-model normalization. Extend PreferencesStoreTests and reset/normalization tests before wiring UI.
5. Add shared optional preflight to onboarding submit, normal submit-and-refresh, and run-now. Preserve a single busy interval, existing success follow-ups, captured context/flag, and check cancellation plus current account/context before upload. Treat superseded work separately from genuine errors.
6. Add event-recorder tests (dedicated `PreSubmitCursorSyncTests.swift` or established existing helpers) for:
   - Off: original submit/fetch and run/fetch/status sequences, zero sync.
   - On: exactly one sync before upload for all three entry points, including online menu action in local mode.
   - Failure: zero upload/profile/status follow-ups and no freshness advance; existing source cache retained and retryable action feedback.
   - Partial JSON failure, zero-row success, duplicate/conflicting actions while sync is suspended.
   - Account or CLI context changes during sync: no old upload or late failure publication; cancellation cannot reach the upload even if a fake sync ignores it.
   - Popover closure: operation continues with existing banner suppression.
   - Automatic ticks/wake, graph refresh, read-only statistics, Cursor login/status, pricing diagnostics, configure/disable: zero explicit preflight sync.
7. Add native immediate-save switch near Agent connection, clear scope/failure help, disabled during explicit operations, stable accessibility identifier. Keep autosubmit draft/Apply semantics unchanged. Extend offline UI smoke tests for toggle persistence and explanatory text.
8. Dispatch trellis-check over the full task scope; run all app/unit/UI tests possible in the environment. Update macOS integration, persistence and testing specs for the new opt-in sequences and unchanged scheduled/automatic/login boundaries.
9. Present checked changes and any remaining manual validation. Request commit-plan approval separately; do not commit or archive merely because implementation was approved.

## Validation commands

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -only-testing:TokChanTests
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS'
python3 ./.trellis/scripts/task.py validate .trellis/tasks/10-15-cursor-sync-before-submit
git diff --check
```

Use deterministic fake services and offline UI fixture mode; never validate by uploading real usage, logging into Cursor, touching user credentials, or invoking real launchd operations. If UI automation is unavailable, state the limitation and leave the gate unverified rather than marking it passed. Do not invoke production signing/release pipelines for this change.

## Review gates / rollback points

- Protocol addition must compile across all test/preview/UI fixtures; no default no-op.
- Preference wiring must survive normalization, launch, and owned-key reset with no CLI/API work triggered by toggling.
- No network command may occur between preflight success and the guarded upload except the upload itself; no extra npx/runtime auto-discovery probes.
- The flag is disabled by default and is the runtime rollback. Code rollback removes only TokChan policy/UI/Boolean; no upstream files or scheduler state need repair.
- Upstream source changes may require JSON compatibility handling later; unknown required response formats fail closed now rather than silently continuing.
- Context validation warns that `tokscale-integration.md` exceeds the 32 KiB injection limit. Implementation/review agents must read that source file completely (paged if needed), including the local-source and mode contracts near its end; injected content alone is not sufficient.
