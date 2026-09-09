# Validation

## Automated checks

Passed on 2026-09-09:

- `python3 -m py_compile scripts/generate-release-notes.py`
- `python3 tests/test_release_notes.py` — 8 tests
- `python3 tests/test_project_version.py` — 7 tests
- `python3 tests/test_ci_signing.py` — 8 tests
- `python3 tests/test_workflow_action_pins.py` — 1 test
- `bash tests/test_release_scripts.sh` — 81 checks
- shell syntax validation embedded in the release-script suite
- `git diff --check`
- `scripts/build-release.sh --output <temporary-directory>` — unit tests, universal Release build, ad-hoc nested signing, DMG layout/verification, Sparkle ZIP verification, checksum, and exact three temporary assets all passed

## Review

The `trellis-check` pass found and fixed one byte-exactness issue: `gh api --jq .body` appends a display newline. Release-body reads now parse raw GitHub API JSON with Python and write the body without adding bytes. Offline mocks cover exact draft creation/correction and published read-only recovery.

The final spec review added the generator signature, fragment good/base/bad cases, and required generator tests to `.trellis/spec/macos/release-workflow.md`.

## Optional tools

- `shellcheck`: not installed
- `actionlint`: not installed

Their absence is non-blocking because shell blocks are syntax-checked and workflow structure/action pins are covered by the offline suite.
