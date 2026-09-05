# Implementation Plan

## Ordered checklist

1. Update release-build prerequisites and asset variables from ZIP to DMG while preserving version, architecture, signing, no-overwrite, and publication-lock contracts.
2. Refactor temporary-resource cleanup to track attached disk-image devices and guarantee detach-before-delete behavior on every success and failure path.
3. Stage the verified `TokChan.app` with an exact `/Applications` symlink, create a writable HFS+ image, attach it at an owned mount point, and persist the approved minimal Finder icon layout using bounded Finder automation.
4. Detach the writable image, convert it to compressed read-only UDZO, and reject any creation, layout, detach, or conversion failure before publication.
5. Verify the compressed image with `hdiutil`, mount it read-only without auto-open, validate its visible root contract and symlink, then re-check App metadata, architectures, and complete ad-hoc signature from the mounted copy.
6. Detach the verification mount, create a basename-relative SHA-256 checksum, and atomically publish only the DMG/checksum pair.
7. Extend shell fixtures and mocks for DMG happy path and failure cleanup, preserving all existing release safety and GitHub draft/publication cases.
8. Update `.github/workflows/release.yml` to validate, upload, and assert the exact DMG/checksum pair while retaining existing warning and immutability behavior.
9. Update `README.md` with DMG build outputs, checksum verification, drag-to-Applications installation, and unchanged Gatekeeper caveats.
10. Run static, fixture, Xcode, and real DMG integration checks; manually inspect the mounted Finder layout before final review.

## Validation commands

```bash
bash -n scripts/build-release.sh scripts/release.sh tests/test_release_scripts.sh
python3 tests/test_project_version.py
bash tests/test_release_scripts.sh
xcodebuild test \
  -project TokChan.xcodeproj \
  -scheme TokChan \
  -destination 'platform=macOS'
rm -rf dist-dmg-check
scripts/build-release.sh --output dist-dmg-check
hdiutil verify dist-dmg-check/TokChan-v*-macos-universal.dmg
(
  cd dist-dmg-check
  shasum -a 256 -c TokChan-v*-macos-universal.dmg.sha256
)
```

Attach the produced DMG read-only at a temporary mount point and assert:

```bash
test -d "$mount/TokChan.app"
test -L "$mount/Applications"
test "$(readlink "$mount/Applications")" = /Applications
lipo -archs "$mount/TokChan.app/Contents/MacOS/TokChan"
codesign --verify --deep --strict --verbose=2 "$mount/TokChan.app"
codesign -dv --verbose=4 "$mount/TokChan.app"
```

Also parse every workflow `run: |` block and syntax-check it with Bash. Run `shellcheck` and `actionlint` when installed.

## Manual verification

- Double-click the generated DMG and confirm Finder opens a compact icon-view window.
- Confirm only the TokChan App and Applications alias are user-visible, with App left and Applications right.
- Drag TokChan into Applications and confirm the copy interaction is offered; do not overwrite an installed copy without explicit user authorization.
- Confirm the mounted App still carries the expected icon and can be launched after any required manual Gatekeeper approval.
- Confirm no temporary TokChan disk image remains attached after successful or intentionally failed builds.

## Review gates before task start

- User approves the final planning summary in a subsequent message.
- `prd.md`, `design.md`, and `implement.md` agree that ZIP is replaced, not retained.
- Both context manifests contain real release/spec entries.
- No Developer ID, notarization, secret management, version bump, Tag push, Release publication, or installed-App replacement has entered scope.

## Risky files and rollback points

- `scripts/build-release.sh`: highest risk; preserve ownership-aware cleanup, signature validation, no-overwrite behavior, and atomic final publication around image attachment state.
- `tests/test_release_scripts.sh`: mocks must verify command and lifecycle semantics without masking failures in the real integration build.
- `.github/workflows/release.yml`: update asset variables, exact-list validation, upload inputs, and mock expectations together.
- `README.md` and `.trellis/spec/macos/release-workflow.md`: never imply that DMG packaging adds Apple-verified identity, notarization, or Gatekeeper trust.
- Roll back packaging script, tests, workflow, docs, and spec as one unit if DMG generation is not reliable on the selected GitHub macOS runner.
