# Implementation Plan

## 1. Build the deterministic generator

- Add `scripts/generate-release-notes.py` with strict CLI parsing, stable SemVer/ancestor resolution, touched-path endpoint comparison, duplicate-key JSON parsing, fragment validation, canonical ordering, and staged output publication.
- Render `github.md`, `sparkle.html`, and `manifest.json` from one canonical model and one set of Chinese security facts.
- Keep the implementation standard-library-only and read source content from Git objects.

Validation gate:

```bash
python3 -m py_compile scripts/generate-release-notes.py
```

Rollback point: generator and its dedicated tests can be reverted before workflow integration.

## 2. Add generator behavior tests

- Add focused Python tests using temporary Git repositories and annotated stable Tags.
- Cover three categories/order, omitted empty categories, prior-fragment exclusion, true first release, divergent/no-ancestor Tags, empty selection, historical modification/deletion/rename/transient fragment, malformed JSON and fields, Chinese/length/normalization rules, duplicates/limit, HTML escaping, exact channel parity, and byte-identical reruns.
- Verify failure leaves no partial output files.

Validation gate:

```bash
python3 tests/test_release_notes.py
```

## 3. Integrate release workflow

- Add a pre-credential `Generate Chinese release notes` step after Tag/source validation and before Release recovery/build credential use.
- Pass generated paths through step outputs or fixed runner-temp paths without adding them to the three Release assets.
- Make appcast generation copy and verify generated Sparkle HTML instead of using the fixed heredoc.
- Replace GitHub generated notes with exact generated Markdown.
- Implement absent/draft/published body rules: create exact draft body, draft-only deterministic PATCH and verification, published read-only exact verification.
- Preserve state rechecks, exact asset verification, release-before-Pages ordering, recovery constraints, permissions, action pins, and credential cleanup.

Rollback point: revert the workflow as one unit if the mocked publication state machine regresses; do not publish a Tag while validation is red.

## 4. Extend offline workflow tests

- Update `tests/test_release_scripts.sh` fixtures and assertions for the new step ordering and generated files.
- Extend the `gh` mock to distinguish draft body PATCH from `draft=false`, record body bytes, and prove published recovery never mutates Release state.
- Assert GitHub automatic notes are disabled, appcast consumes generated HTML, manifest stays private, generation precedes credentials/mutations, and Pages remains last.
- Keep existing syntax, action-pin, signing/notarization, asset, feed-history, and recovery tests green.

Validation gate:

```bash
bash -n .github/workflows/release.yml tests/test_release_scripts.sh
bash tests/test_release_scripts.sh
python3 tests/test_workflow_action_pins.py
```

## 5. Document contributor and maintainer usage

- Update `.trellis/spec/macos/release-workflow.md` so Trellis planning classifies release-note impact, implementation adds one fragment per user-visible outcome, and full-scope quality check compares the changed behavior against fragment coverage before completion.
- Update `docs/macos-release.md` with fragment path/schema, category guidance, user-outcome examples, permanent lifecycle, empty-fragment failure, and correction workflow before Tag creation.
- Explain that future GitHub/Sparkle notes are Chinese and deterministic while historical releases remain unchanged.
- Do not add a general pull-request or push CI workflow; record direct non-Trellis commits as an accepted enforcement limitation.

## 6. Full verification

Run the release-workflow contract checks:

```bash
bash -n scripts/build-release.sh scripts/ci-build-release.sh scripts/release.sh tests/test_release_scripts.sh
python3 -m py_compile scripts/generate-release-notes.py
python3 tests/test_release_notes.py
python3 tests/test_project_version.py
python3 tests/test_ci_signing.py
python3 tests/test_workflow_action_pins.py
bash tests/test_release_scripts.sh
scripts/build-release.sh
```

Also run `shellcheck` and `actionlint` when installed. Inspect `git diff --check`, confirm exactly three Release assets remain, and verify no generated manifest, private key, ZIP, credential path, or unexpected file can enter the Pages artifact.

## Review gates before activation

- PRD, design, and this plan are approved by the user.
- `implement.jsonl` and `check.jsonl` contain the macOS release-workflow spec and release-note research artifact.
- No implementation begins until `task.py start` succeeds.
