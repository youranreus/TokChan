# Commit plan and closeout

1. `feat: 增加提交前 Cursor 同步配置`

Product:
- TokChan/Features/Dashboard/DashboardView+Preview.swift
- TokChan/Features/Dashboard/DashboardViewModel.swift
- TokChan/Features/Settings/SettingsView.swift
- TokChan/Shared/Services/PreferencesStore.swift
- TokChan/Shared/Services/TokscaleCLIClient.swift

Tests:
- TokChanTests/CursorSyncCLITests.swift
- TokChanTests/PreSubmitCursorSyncTests.swift
- TokChanTests/DashboardDataModeTests.swift
- TokChanTests/DashboardLayoutTests.swift
- TokChanTests/DashboardViewModelTests.swift
- TokChanTests/DiscoveryRaceTests.swift
- TokChanTests/OperationBannerLifecycleTests.swift
- TokChanTests/PreferencesStoreTests.swift
- TokChanUITests/TokChanUITests.swift

Specs (same coherent feature commit):
- .trellis/spec/macos/cursor-pre-submit-sync.md
- .trellis/spec/macos/data-persistence.md
- .trellis/spec/macos/index.md
- .trellis/spec/macos/swiftui-guidelines.md
- .trellis/spec/macos/testing-guidelines.md
- .trellis/spec/macos/tokscale-integration.md

Planning and verification artifacts:
- .trellis/tasks/10-15-cursor-sync-before-submit/task.json
- .trellis/tasks/10-15-cursor-sync-before-submit/prd.md
- .trellis/tasks/10-15-cursor-sync-before-submit/design.md
- .trellis/tasks/10-15-cursor-sync-before-submit/implement.md
- .trellis/tasks/10-15-cursor-sync-before-submit/implement.jsonl
- .trellis/tasks/10-15-cursor-sync-before-submit/check.jsonl
- .trellis/tasks/10-15-cursor-sync-before-submit/research/entry-points-and-contract.md
- .trellis/tasks/10-15-cursor-sync-before-submit/verification.md
- .trellis/tasks/10-15-cursor-sync-before-submit/commit-plan.md

The user approved the feature commit above; it landed as `b2678b7`. No archive or journal bookkeeping was mixed into it. Validation: 298 unit tests and unsigned Release builds passed. Five automated UI tests remain skipped; subsequent user acceptance of the local Debug app closes the manual gate, not the automated tests.

## Follow-up plan (approved by the user's “行”)

1. `docs: 补充 Cursor 提交前同步发布片段与验收记录`
   - release-notes/fragments/20261015-cursor-sync-before-submit.json
   - .trellis/tasks/10-15-cursor-sync-before-submit/prd.md
   - .trellis/tasks/10-15-cursor-sync-before-submit/implement.md
   - .trellis/tasks/10-15-cursor-sync-before-submit/verification.md
   - .trellis/tasks/10-15-cursor-sync-before-submit/commit-plan.md
2. `chore(task): archive 10-15-cursor-sync-before-submit`
   - Archive the current task using the Trellis script after the work commit.
3. `chore: record journal`
   - Record the feature and follow-up work commit hashes in the developer journal.

Unrecognized dirty files: none at preparation. No amend, push or release. The archive/journal scripts own their bookkeeping commits.
