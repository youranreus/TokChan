# Proposed commit (awaiting user approval)

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

Unrecognized dirty files: none. No archive or journal bookkeeping is mixed into this work commit. Do not commit automatically; the user's implementation approval is not commit approval. No push/amend.

Validation: 298 unit tests passed; unsigned Release build passed. Five UI tests skipped because SystemUIServer did not expose the status item; UI acceptance remains unverified and documented in verification.md. Committing does not mark this gate complete or archive the task.
