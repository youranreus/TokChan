# Technical Design

## Boundary

Keep recovery inside `TokscaleCLIClient`, where raw `ProcessOutput` and the exact command are available. `DashboardViewModel` remains unaware of launchd and retains its existing `configure → status` orchestration.

The exception is intentionally narrow: only `.configureAutosubmit` may invoke the recovery path. No scheduler abstraction or plist management is added.

## Flow

1. Build and execute the existing versioned `npx ... autosubmit enable ...` command.
2. If it succeeds, return unchanged.
3. If it fails, classify the combined raw stdout/stderr using all known signatures of the upstream defect:
   - outer Tokscale command failed;
   - `launchd bootout failed`;
   - command text contains `launchctl bootout --wait`;
   - nested launchctl status is 64;
   - `Unrecognized target specifier`.
4. On an exact match, execute `/bin/launchctl` with discrete arguments:
   - `bootout`
   - `gui/<effective uid>/ai.tokscale.autosubmit`
5. Require exit code 0. A failure is surfaced as a Tokscale-facing localized error with sanitized diagnostics.
6. Execute the same configured Tokscale version's `autosubmit disable` command once with only `TOKSCALE_AUTOSUBMIT_SKIP_SCHEDULER=1` added to its child environment. This delegates persistent state and managed-executable cleanup to Tokscale while preventing its broken launchd cleanup from running again.
7. Require disable exit code 0. A failure stops before re-enable and is surfaced as compatibility-state-cleanup failure.
8. Execute the identical original `npx ... autosubmit enable ...` arguments exactly once more through the normal runner and normal environment.
9. Return success or the retry error. The existing view model then performs its one status read.

## Contracts

- The service label and `/bin/launchctl` path are constants, not derived from CLI output.
- The GUI domain uses the effective process UID (`geteuid`) to match the current app user.
- No `/bin/sh`, interpolation, globbing, plist mutation, settings-file mutation, or arbitrary command execution.
- The state cleanup is the official Tokscale `autosubmit disable` command using the same configured package version and npx executable; TokChan does not infer paths or edit Tokscale files itself.
- Environment injection is scoped only to that recovery-disable child process and sets `TOKSCALE_AUTOSUBMIT_SKIP_SCHEDULER=1`; the original enable retry receives its normal environment.
- Classification examines raw output before generic `TokscaleCLIError.failed` conversion so stdout and stderr signals are not lost.
- Each recovery step and the final retry are structurally bounded to one call and do not recursively invoke recovery.

## Error Semantics

- Initial nonmatching failure: preserve existing `TokscaleCLIError.failed` behavior.
- Recovery bootout failure: throw a dedicated/sanitized failure that identifies launchd cleanup as the failed step and includes exit details.
- Recovery disable failure: stop before re-enable and identify Tokscale state cleanup as the failed step.
- Retry failure: preserve the retry command's normal CLI error.
- A missing service is not silently accepted in this initial compatibility path: the exact reproduced defect means Tokscale observed an existing service, and swallowing unrelated launchctl failures could hide a race or permissions issue.

## Compatibility and Removal

This temporarily relaxes `.trellis/spec/macos/tokscale-integration.md` only for the exact upstream defect. Add an explicit documented exception with removal criteria. Once supported Tokscale releases no longer emit this command, remove the classifier, direct launchctl call, recovery-disable environment override, tests, and spec exception together.

## Rollback

All behavior is localized to the CLI adapter. Reverting the adapter changes and spec exception restores the previous pure-wrapper behavior without data migration.
