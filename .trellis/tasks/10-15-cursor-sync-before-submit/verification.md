# Verification

## Approval / implementation

The user approved the final planning summary with “开始”. Task status was changed to in_progress before dispatch. trellis-implement implemented the approved default-off setting, strict Cursor sync CLI boundary, all three preflight entry points and offline tests. Independent trellis-check found no in-scope defects and made no edits. No real Tokscale/npx command, usage upload, credential access or launchd operation was performed during implementation/check.

## Automated evidence

- Baseline implement-agent unit suite: 275 passing tests.
- Final implement-agent unit suite: 298 passing tests.
- Independent check command:
  `xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -disableAutomaticPackageResolution -skipPackageUpdates`
- Independent log `/tmp/tokchan-check-full.log`: 298 unit tests, zero failures (lines 804-806). Five UI tests executed but skipped because SystemUIServer did not expose menu bar items (lines 862-1058). The new toggle UI gate was explicitly reported unverified at line 958.
- Release build command:
  `xcodebuild build -project TokChan.xcodeproj -scheme TokChan -configuration Release -destination 'platform=macOS' -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO`
- `/tmp/tokchan-check-build.log:701`: BUILD SUCCEEDED. Check agent verified arm64/x86_64 compilation with macOS 13 deployment target. This unsigned build does not establish signing/notarization/release readiness.
- `git diff --check`: passed after implementation, independent review and spec updates.
- `task.py validate`: passed. Existing integration spec exceeds the injection cap; agents read the full source as required, and the new focused contract is linked from the spec index.

Temporary log paths are local session evidence and are not committed artifacts.

## Specs captured

Added `.trellis/spec/macos/cursor-pre-submit-sync.md` with command/JSON fields, default-off preference, failure matrix, revision/cancellation guard, test assertions, scheduler exclusions and wrong/correct examples. Linked it from the macOS index, integration, persistence, SwiftUI and testing guides. Previous command-count contracts are default-off sequences extended by this explicit opt-in exception.

## Remaining gate

UI acceptance is not verified; do not interpret skipped UI tests as passed. On an interactive desktop, use the Debug offline UI-test fixture and verify:
1. General Settings shows “提交前同步 Cursor” near Agent connection, off by default, with explicit scheduled-autosubmit exclusion and failure-stop copy.
2. Toggling saves without Autosubmit Apply and survives Settings close/reopen.
3. The control is disabled during explicit work and fits the window in light/dark appearance.

The task is not archived and no commit has been made. Commit approval and UI verification remain separate user actions.
