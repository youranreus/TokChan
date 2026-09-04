# Implementation plan

## Gate

- [x] User authorized Trellis task creation.
- [x] User chose Tokscale API as the authoritative range definition.
- [x] Verified official source and live week/month contracts.
- [x] PRD convergence and design/context preparation complete.
- [x] User approved final summary; task started.

## Work sequence

1. Load curated macOS guidelines and research; use the configured Trellis implementation agent workflow after approval. Assign any worker a bounded responsibility and the active task path, preventing overlapping edits.
2. Add period/request/response contracts and coherent mapped breakdown data. Update deterministic fixtures, previews and API fakes.
3. Implement scope selection, stale response protection and cache compatibility across load, refresh, run-now and account changes.
4. Download full official client asset inventory with provenance and add bundled images plus alias/fallback mapping.
5. Implement fixed dashboard sections, segmented scope picker, breakdown bar/legend, independent client scrolling and expandable top-five model lists; use Tokens wording.
6. Move autosubmit status and run-now feedback into settings, preserving existing controls and Save behavior.
7. Run Trellis quality review, focused tests for scope correctness, cache hydration/invalidation, token fractions, client top-five behavior and API encoding. Inspect UI with deterministic data for empty/large lists, errors and both appearances.
8. Run xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-usage-periods-test; avoid live network and CLI in fixtures.
9. Build Release with xcodebuild -project TokChan.xcodeproj -scheme TokChan -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-usage-periods-release build; verify bundle signature and embedded asset lookup.
10. Review new contracts for spec updates, inspect task-owned diff, present commit grouping for approval under repository workflow, then provide app path and verification results.

## Review focus

- UI must never show one period's data under another selected tab.
- Scope switching must never submit or change autosubmit configuration.
- Reopening, background failures and rapid scope/account changes remain coherent.
- The 380×680 panel has only client scrolling and readable five-category legend.
- Model expansion leaves totals unchanged and resets on range change.
- Settings success/failure/progress and native opening remain usable.
- Every official client image is bundled; unknown client fallback works offline.

## Completion record

Implementation and spec updates complete. Initial implement agents were unavailable (HTTP 403); root implemented inline. A later independent check agent reviewed data flow, and both race findings were fixed with regression coverage. Code remains uncommitted pending the repository's explicit commit confirmation gate.

Validation evidence and limitations are recorded in verification.md. No unrelated dirty files were present when work began.
