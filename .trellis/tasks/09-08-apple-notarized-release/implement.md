# Implementation plan

User explicitly approved the plan on 2026-09-08. Task activated; implementation and available validation completed. See validation.md. Real Apple acceptance remains credential-dependent.

1. Inspect resolved signing capabilities and release test harness, finalize exact helper boundaries.
2. Implement explicit public signing/notarization path with fail-closed validation and ordered finalization.
3. Wire temporary CI credentials, cleanup, and updated draft release body checks.
4. Document certificate creation/export, GitHub secret names, local build behavior and first-launch expectations; update release spec.
5. Run bash syntax validation, existing Python release tests and new behavioral trust-boundary tests; validate YAML and run universal build/unit tests as available.
6. After credentials are configured, validate real notarization/stapling and clean-Mac launch. Report unavailable checks honestly; do not publish or push without authorization.

Preserve the current clean worktree baseline and avoid unrelated application changes.
