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

## Manual acceptance and commit status

The feature was committed with user approval as `b2678b7 feat: 增加提交前 Cursor 同步配置` (29 files). No push or release was performed.

An ad-hoc signed local Debug app was built and its signature verified. The installed app process was stopped and the local build opened with the user's existing preferences; `/Applications/TokChan.app` was not replaced. This was not an offline UI-test launch, so user-initiated submissions could upload real usage. The assistant did not initiate an upload.

The user completed manual acceptance and replied “没问题，继续后续流程，记得记录fragment”. This closes the manual UI acceptance gate. The five automated UI tests remain skipped, not passed; the user's acceptance does not change the automated results above.

Release fragment: `release-notes/fragments/20261015-cursor-sync-before-submit.json`. The user approved the grouped follow-up documentation/fragment commit, task archive and session journal with “行”. Eight release-notes tests, `git diff --check` and task context validation passed before closeout. No push or release is authorized.
