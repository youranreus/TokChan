# Cursor pre-submit sync: evidence and constraints

## Runtime evidence supplied by the user

The user runs `npx tokscale@latest`, not necessarily the globally installed CLI. Explicit `cursor sync --json` returned `{"synced":true,"rows":7046,"error":null}`. A following Cursor-only, today-filtered submit dry run reported a 15-second budget exceeded while requesting page 11 (10 pages, 5000 of 7054 events collected), then used cached data. Its summary contained Cursor tokens and cost: it was stale-data fallback, not proof that Cursor was entirely excluded.

Earlier global `tokscale 4.15.0` status/dry-run observations must not be used as evidence about the CLI version resolved by TokChan.

Related upstream reports:
- https://github.com/junhoyeo/tokscale/issues/1175 — Cursor CSV downloads exceeding the 15-second timeout.
- https://github.com/junhoyeo/tokscale/pull/1183 — longer timeout for explicit sync.
- https://github.com/junhoyeo/tokscale/blob/v4.15.0/crates/tokscale-cli/src/cursor.rs — explicit sync uses `sync_cursor_cache(true)`, implicit sync uses the shorter default; JSON sync returns structured failure even with exit code zero.
These sources describe the historical implementation, not a guarantee about latest paging details. The user's latest-version output independently confirms the short implicit budget remains relevant. No additional live sync/upload is needed to plan this adapter feature.

## Repository evidence

- `TokChan/Shared/Services/TokscaleCLIClient.swift:26-48`: commands use npx `--yes tokscale@<configured version>`; submit is bare submit and run-now is `autosubmit run --force`.
- `TokChan/Shared/Services/TokscaleCLIClient.swift:409-415`: default process timeout is 300 seconds.
- `TokChan/Shared/Services/TokscaleCLIClient.swift:438-440,533-535`: service methods discard successful command output; JSON sync must be a new validated service operation, not another void unchecked command.
- `TokChan/Features/Dashboard/DashboardViewModel.swift:564-604`: onboarding first submit is a separate upload entry point.
- `TokChan/Features/Dashboard/DashboardViewModel.swift:611-614,630-659`: online panel refresh delegates to normal submit-and-refresh; menu routes through the same action.
- `TokChan/Features/Dashboard/DashboardViewModel.swift:684-708`: run-now invokes the upstream CLI, then reads online profiles and autosubmit status.
- `TokChan/Features/Dashboard/DashboardViewModel.swift:1286-1294`: configured context resolves npx and version once. A setting of `latest` is a selector, not an immutable package version.
- `TokChan/Features/Dashboard/DashboardViewModel.swift:1329-1344`: normalization reconstructs preferences; a new property must be explicitly preserved here.
- `TokChan/Shared/Services/PreferencesStore.swift:11-66,85-160`: preferences are explicit UserDefaults keys, with missing-key defaults and an owned-key reset list. No Codable cache migration is needed for this Boolean.
- `TokChan/Features/Settings/SettingsView.swift:254-273`: General groups basic CLI configuration and Agent connection; a local immediate-save toggle fits here, separate from the autosubmit draft Apply button.

## Boundaries

TokChan must not read Cursor credentials/cache itself or edit upstream settings/scheduler files. The setting controls only explicit TokChan-initiated uploads, never ticks, wake, graph refresh, login/status, pricing dry-run, or external scheduled runs. Upstream submit may still attempt its own sync after preflight; this feature prepares a fresher fallback cache and cannot guarantee server freshness at the exact upload instant.

A new await before upload creates a new safety boundary: capture account/context/setting at action start, then check cancellation and reject account/context changes before issuing the upload. Keep the existing explicit-operation exclusion active across both commands; closing the popover must not cancel an explicit upload sequence. Do not dynamically enable or disable the preflight halfway through an operation.

## Suggested deterministic validation

Extend command-builder and CLI fake-runner tests for exact suffix, structured success, zero-row success, malformed/unknown JSON, partial/multi-account error and process failures. Extend view-model event recorder tests for all three upload entry points, concurrency, account/context changes during sync, and unchanged automatic paths. Extend preference missing-key, round-trip, normalization, and reset checks. Use offline UI fixtures only.
