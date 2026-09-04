# Implementation Plan

1. Refactor `NpxLocator` into a deterministic candidate pipeline while preserving override, inherited PATH and fixed-system precedence.
2. Add safe helpers for absolute environment roots, stable path deduplication, strict semantic-version parsing/sorting, bounded directory enumeration and exact config-token parsing.
3. Implement selected/default and installed-version candidates for fnm, Volta, asdf, mise, nodenv, n and nvm according to `design.md`; never execute managers, profiles or excluded shims.
4. Expand `NpxLocatorTests` with isolated fixtures covering each default layout, environment-root overrides, selected/default preference, semantic fallback, deterministic cross-manager ordering and malicious/invalid inputs.
5. Verify the existing settings presentation and ProcessRunner sibling-Node behavior remain unchanged.
6. Update `.trellis/spec/macos/tokscale-integration.md` with the expanded discovery contract and required test matrix.

## Validation

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS'
git diff --check
```

Also run focused `NpxLocatorTests` during iteration.

## Review gates

- Confirm no discovery path starts a process, shell or network operation.
- Confirm every environment-derived root is absolute and every config-derived child is narrowly validated.
- Confirm tests inject an isolated home/environment/fixed candidate set and do not depend on developer-machine installations.
- Confirm `dist-local/` remains untracked and excluded from commits.

## Rollback points

- Manager adapters are independent candidate builders and can be removed individually.
- No schema or preference migration is introduced; reverting `NpxLocator` and its tests restores prior behavior.
