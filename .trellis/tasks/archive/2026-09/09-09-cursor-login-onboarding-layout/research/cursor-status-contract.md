# Cursor status contract research

## Sources

- TokChan current CLI boundary and settings lifecycle.
- Tokscale upstream default branch, `crates/tokscale-cli/src/main.rs` and `crates/tokscale-cli/src/cursor.rs`, inspected 2026-09-09.
- Previous task `.trellis/tasks/archive/2026-09/09-09-onboarding-agent-login/`.

## Upstream command

Tokscale exposes:

```text
npx --yes tokscale@<version> cursor status
```

`cursor status` has no JSON flag. It loads the active saved Cursor account and validates its session against Cursor's usage-summary endpoint.

## Observable output classes

After ANSI control sequences are removed:

- Valid session: output contains the exact line content `Session: Valid` (allowing surrounding whitespace).
- No saved account: output contains `No saved Cursor accounts.` and suggests running Cursor login.
- Saved but explicitly expired/invalid session: output contains `Session: Session token expired or invalid`.
- Connectivity, HTTP, parse, or response-format failures are also printed after `Session:` even though they do not prove the saved credential is unusable.
- Process failures (missing npx, invalid package version, timeout, non-zero exit) are already represented by TokChan's command-context/process error types.

The upstream function returns success for its ordinary no-account and invalid-session display paths, so process exit status alone cannot classify availability. Conversely, arbitrary output or connectivity-shaped text must not be treated as proof that no usable login exists.

## Parsing decision

Use a small deterministic parser over ANSI-stripped stdout/stderr:

1. `Session: Valid` -> valid.
2. `No saved Cursor accounts.` -> unavailable / login may be offered.
3. `Session: Session token expired or invalid` -> unavailable / login may be offered.
4. Connectivity, HTTP, parse/format, empty, or structurally unknown output -> indeterminate failure / retry only.
5. Process/context error -> indeterminate failure / retry only.

Do not include raw account identifiers, user IDs, tokens, or complete command output in persisted state or routine diagnostics. A bounded sanitized error may be shown for explicit retry guidance.

## Lifecycle decision

The existing settings visibility boundary collapses `.task`, `.onAppear`, and active scene callbacks within one continuous presentation. Add Cursor status refresh to that boundary, and clear transient Cursor success/failure feedback on the hidden transition. A new visible period starts from checking state and queries again.
