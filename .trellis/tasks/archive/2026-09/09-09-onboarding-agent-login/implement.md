# Implementation Plan

## 1. Lock command behavior with tests

- Add `.cursorLogin` command-builder coverage for the exact `cursor login` suffix and existing version rejection.
- Add CLI-client/fake-runner coverage proving one process launch through the resolved npx executable and no shell.
- Extend every `TokscaleCLIService` fake and preview implementation with deterministic Cursor login behavior.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -only-testing:TokChanTests/CLICommandBuilderTests
```

Rollback point: command enum/protocol additions only.

## 2. Convert identity discovery to explicit user action

- Change empty-username initial reconciliation to the editable username-entry state.
- Refactor `load()` so empty preferences never call `whoAmI`, while preserving unrelated status behavior.
- Add `discoverIdentity()` and reuse the existing normalized preference update plus complete-batch verification path.
- Preserve duplicate-operation guards and Settings-wins race handling.
- Replace automatic-discovery tests with explicit-trigger tests covering initial silence, success, failure, duplicate clicks, and concurrent Settings username changes.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -only-testing:TokChanTests/DashboardViewModelTests -only-testing:TokChanTests/DiscoveryRaceTests
```

Rollback point: onboarding state/refactor before UI changes.

## 3. Add shared Cursor login orchestration

- Add the dedicated Cursor login state to `DashboardViewModel`.
- Implement `loginCursor()` using the current persisted command context and `TokscaleCLIService.loginCursor`.
- Integrate login into the shared operation-exclusion/busy projection.
- Publish bounded success/failure feedback and the version-specific terminal fallback command.
- Test exact event counts: one login; zero sync, submit, fetch, status, configure, disable, or run-now follow-ups.
- Test missing npx, invalid version, CLI failure, timeout/fake failure, and duplicate/conflicting operations.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -only-testing:TokChanTests/DashboardViewModelTests
```

Rollback point: remove the login state/method while retaining command support.

## 4. Build onboarding and Settings UI

- Add the manual “识别本机登录” action and stable accessibility identifier to step one.
- Add a compact optional Cursor login module to onboarding without adding a third required step.
- Add the same Cursor login capability to a General Settings Agent section.
- Reuse a small shared view/helper for login state, fallback command display, copy action, and identifiers where it improves consistency.
- Ensure buttons disable during conflicting work and feedback remains bounded/selectable.
- Update previews and fixed-size layout tests for idle, running, success, and failure states in light/dark appearances.
- Add or update offline UI smoke assertions; never invoke real npx or network services.

Validation gate:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -only-testing:TokChanTests/DashboardLayoutTests -only-testing:TokChanTests/SettingsWindowActionTests
```

Rollback point: remove shared UI module and both placements without changing service behavior.

## 5. Full quality and contract pass

- Verify every acceptance criterion against tests and rendered states.
- Run the full macOS suite.
- Review changes against SwiftUI, state-management, testing, and Tokscale integration specs.
- Update the Tokscale integration spec to replace automatic first-use discovery with explicit discovery and document the fixed Cursor login contract.
- Confirm README onboarding/Cursor instructions remain accurate or update them if UI behavior changed materially.

Validation commands:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS'
git diff --check
git status --short
```

## Risk Notes

- `TokscaleCLIService` is widely faked; missing one conformance will surface as a compile failure.
- Cursor CLI may fall back to stdin interaction. TokChan must not add token capture or hang-specific prompt parsing; failures direct users to the terminal command.
- `DashboardOperation` and onboarding busy state currently gate multiple commands. Review every entry point after adding Cursor login so mutual exclusion is symmetric.
- The onboarding viewport is fixed at 380×680; long CLI errors and command text must not crowd out the username path.
