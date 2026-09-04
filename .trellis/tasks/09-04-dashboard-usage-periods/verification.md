# Verification

## Delivered behavior

- all/week/month server scopes, matching cards/rank/dateRange, breakdown and client groups.
- Fixed header/controls/metrics/breakdown/footer; only client list scrolls.
- Top-five model rows with expand/collapse and reset on scope change.
- 31 client originals plus bundled asset sets and provenance/license, unknown-client fallback.
- Autosubmit status and run-now moved to settings, preserving progress/error/success and saved configuration semantics.
- Tokens wording throughout the product.

## Checks

- Clean full test run: 37 unit tests plus 1 UI launch smoke test passed, 0 failures. Log: /private/tmp/TokChan-usage-periods-clean-test.log.
- Final follow-up: 2 discovery/settings race tests passed after hardening the failure path. Log: /private/tmp/TokChan-discovery-final.log.
- Release build succeeded after all product fixes: /private/tmp/TokChan-usage-periods-release.log.
- Final app: /private/tmp/TokChan-usage-periods-release/Build/Products/Release/TokChan.app, universal arm64/x86_64, local signature verified with codesign --verify --deep --strict.
- All 31 bundled original image hashes equal the project sources; every known asset name loaded successfully in tests.
- Actual SwiftUI rendering at 380×680 reviewed in light and dark: /private/tmp/TokChan-dashboard-light.png and /private/tmp/TokChan-dashboard-dark.png.
- git diff --check passed; product text contains no 令牌数.

## Review fixes

1. Initial whoAmI can resume after Settings changes npx/version. Recompute current context after success or failure; tests hold discovery suspended across a save.
2. A profile reload superseded by scope selection cannot be treated as an updated profile. Return explicit updated/failed/superseded outcomes and use the caller's result instead of shared error state.

## Environment notes and limits

The reused derived-data directory produced a pre-existing ProcessRunnerTests 2-second timeout after an earlier successful run. The same baseline test passed in a separate directory; the full current suite also passed in a new derived-data directory without changing ProcessRunner code or its timeout.

Native UI tool read the initial fixture accessibility tree (correct tabs, five model rows and dedicated scroll area), then repeatedly timed out. Interactive click/scroll verification through that tool was not completed. Visual QA used actual SwiftUI bitmap rendering instead; automated UI coverage is the existing launch smoke test. No real submission was performed for testing.

## Commit state

All task changes are ready for review. No commit, push, or archive performed; awaiting commit confirmation as required by workflow.md.

## Cache-first and daily follow-up

41 unit tests passed after this revision, including complete four-scope cache JSON reconstruction/no-network reopening, single-scope migration, preserved scopes after submit, and server-date daily projection with nil rank. Log: /private/tmp/TokChan-cache-first-test.log. Updated Release: /private/tmp/TokChan-cache-first-release/Build/Products/Release/TokChan.app.

Verified current official user route directory contains devices, groups and route.ts only. Live ?period=day returned period=all with 345 daily contributions, confirming daily data is present in the payload but is not a remote period option. Initial network auto-approval service 403 was transient; authorized read-only retries succeeded.

Final cache review also fixed selection persistence before a missing-scope request completes. The focused DashboardViewModelTests suite passed after adding the failed-day-load/reopen regression; log: /private/tmp/TokChan-cache-selection-test.log. The Release app was rebuilt and its local signature verified after that fix.
