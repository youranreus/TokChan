# Implementation Plan

1. Extend the process-running boundary so a recovery-only child environment override can be injected deterministically without changing normal `npx` PATH behavior; keep production launchctl fixed to `/bin/launchctl` and the effective UID.
2. Add an exact classifier for the known Tokscale `bootout --wait` exit-64 diagnostic.
3. Route only `configureAutosubmit` through a nonrecursive `enable → classify → bootout → Tokscale disable with scheduler skipped → single enable retry` flow; retain generic command behavior elsewhere.
4. Add focused CLI-client tests for:
   - ordinary configure success;
   - exact defect recovery and full call ordering/arguments/environment;
   - near-match rejection;
   - launchctl failure propagation;
   - recovery-disable failure propagation;
   - retry failure propagation and bounded call count;
   - environment override isolation from the original and retried enable commands.
5. Update the Tokscale integration spec with the narrow temporary exception and removal condition.
6. Run focused tests, then the complete macOS test suite and Release build per project guidance.
7. Manually reproduce with the local LaunchAgent, apply a changed configuration through the built app/testable boundary, and verify `launchctl print` plus `autosubmit status --json`; restore the original interval/configuration if the verification changes it.

## Validation Commands

- Focused test invocation for the new CLI adapter test class via `xcodebuild`.
- Full project test command discovered from project specs/workflow.
- Release configuration build.
- `launchctl print gui/$(id -u)/ai.tokscale.autosubmit`
- Current configured `npx --yes tokscale@<version> autosubmit status --json`

## Risk and Rollback Gates

- Before direct launchctl execution: require every defect signature; a failed near-match test blocks implementation.
- Before retry: require successful bootout and successful official Tokscale state cleanup; never proceed after either cleanup failure.
- Before completion: prove each recovery step runs at most once, the service target is fixed, and the scheduler-skip environment variable cannot leak to enable.
- Rollback by reverting the CLI adapter/process-boundary changes, tests, and temporary spec exception together; no persistent schema migration exists.
