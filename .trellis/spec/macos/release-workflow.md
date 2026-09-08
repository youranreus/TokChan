# Build and Release Workflow

## 1. Scope / Trigger

Use this contract whenever changing TokChan version settings, release packaging, Git Tags, or `.github/workflows/release.yml`.

Official GitHub Releases contain one universal drag-to-install DMG and its SHA-256 checksum. CI requires Developer ID Application signing, Apple notarization, and stapled tickets for both app and DMG. Credential-free local builds retain ad-hoc signing for iteration and must not be uploaded as official assets. Historical published releases remain immutable.

## 2. Signatures

Local commands:

```text
scripts/build-release.sh [--output <directory>] [--skip-tests] [--notarize]
scripts/ci-build-release.sh
scripts/release.sh {patch|minor|major} [--push]
python3 scripts/lib/project-version.py <project.pbxproj> get
python3 scripts/lib/project-version.py <project.pbxproj> set --marketing X.Y.Z --build N
```

Release assets:

```text
TokChan-vX.Y.Z-macos-universal.dmg
TokChan-vX.Y.Z-macos-universal.dmg.sha256
```

Git contract:

```text
commit: chore(release): vX.Y.Z
annotated Tag: vX.Y.Z
Tag message: TokChan vX.Y.Z
```

## 3. Contracts

- `MARKETING_VERSION` is stable SemVer `X.Y.Z` and is the user-visible source version. Release preparation increments patch as `X.Y.(Z+1)`, minor as `X.(Y+1).0`, or major as `(X+1).0.0`.
- `CURRENT_PROJECT_VERSION` is a positive integer incremented once per release, regardless of the marketing-version increment type.
- Local release preparation requires Git and Python, not GitHub CLI. It checks Git Tags; GitHub Release API checks and mutation belong to CI after Tag push.
- Debug and Release app-target settings must match and use `VERSIONING_SYSTEM = apple-generic`.
- The Tag must equal `v${MARKETING_VERSION}`; CI never substitutes another version.
- `build-release.sh` runs `TokChanTests` unless `--skip-tests` is explicitly used for local iteration.
- Xcode compilation remains credential-free with automatic signing disabled. Explicit `--notarize` signs the complete outer app with Developer ID Application, `--options runtime` and `--timestamp`; default local mode uses `--sign -`. Never use signing-time `--deep` to hide nested-code ordering problems. Do not add broad hardened-runtime exception entitlements without evidence.
- The built executable must contain `arm64` and `x86_64`; bundle identifier must be `com.youranreus.TokChan`.
- Before packaging, strict `codesign --verify --deep --strict --verbose=2` verification and `codesign -dv --verbose=4` inspection must prove the expected designated identifier, the selected signature mode, Info.plist coverage, and sealed resources. Official mode additionally requires the expected Developer ID authority, Team ID, secure timestamp, and hardened runtime.
- DMG staging contains `TokChan.app` plus an `Applications` symbolic link whose target is exactly `/Applications`. The image uses a writable HFS+ layout phase followed by compressed read-only UDZO conversion; no third-party packaging dependency or committed `.DS_Store` template is allowed.
- Finder layout automation must persist `.DS_Store` metadata for icon view, a fixed compact window, hidden toolbar/status bar, and App-left/Applications-right icon positions. Layout failure is fatal and no custom background is used.
- `hdiutil attach -plist` output must be parsed structurally. Every image mounts at a current-run owned path, auto-open is disabled for verification, and every tracked attachment must detach before temporary workspace deletion.
- Before publication, `hdiutil verify` must pass. The compressed DMG is then mounted read-only and must expose only `TokChan.app` and `Applications` as user-visible root entries; the mounted App must pass version, build, identifier, architecture, strict signature, and signature-metadata verification.
- Official mode submits a ZIP of the signed app, requires notarization `Accepted`, then staples and validates the app before DMG staging. Sign the compressed DMG, require its own accepted notarization, staple and validate it, then verify the DMG and mounted app (including stapled app ticket and Gatekeeper assessment). Any failure is fatal.
- Generate the checksum only after signing and stapling have finished; it records the DMG basename so `shasum -a 256 -c` works after download.
- Final local assets are never overwritten. A publication lock serializes the final pair, and cleanup removes only resources owned by the current run.
- Cleanup removes only resources owned by the current run. If an owned image cannot be detached, fail and retain the workspace rather than deleting a live mount point; partial final publication removes only the files marked as created by that run.
- The release workflow uses `GITHUB_TOKEN` with `contents: write`, one fixed macOS/Xcode job, same-Tag concurrency, and six Apple secrets scoped to the signing step. `scripts/ci-build-release.sh` imports the P12 into an owned temporary keychain, stores notary credentials, invokes `--notarize`, then restores the search list and deletes credentials on success or failure. No certificate/password is committed or logged. Restore the caller umask before building so the private credential-file policy does not produce inaccessible app resources. Cleanup failure fails CI before publication. Apple submission/verification diagnostics must remain visible in failed Actions job logs; a runner-local path alone is insufficient.
- GitHub Release publication is `absent -> draft -> exact asset pair -> published`. A draft may be resumed; a published Release is never overwritten.
- Official release notes must state Developer ID signing, Apple notarization, stapled app/DMG tickets, checksum guidance, and normal Internet-download confirmation. Reject drafts missing the new notes or retaining obsolete unsigned-distribution claims; published releases are untouched. Local ad-hoc output must still clearly disclose its limits. Never promise to disable OS verification or guarantee no first-launch prompt.

## 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Debug/Release version drift | Fail before tests or packaging |
| Invalid SemVer or non-positive build | Fail without editing or publishing assets |
| Existing final asset or foreign publication lock | Fail without deleting or replacing the existing resource |
| Missing/invalid signing credentials, signing identity/team mismatch, missing runtime/timestamp, rejected/pending/timed-out notarization, failed stapling or Gatekeeper assessment | Fail before publication without unsigned fallback |
| DMG creation, Finder layout, attach/plist parsing, detach, conversion, image/content validation, metadata, architecture, signing, strict signature inspection, or checksum failure | Fail and leave no final-named new asset; retain the workspace if a live owned mount cannot be detached |
| Dirty tree, non-`master`, or `HEAD != origin/master` | Refuse release preparation |
| Local or remote Tag already exists | Local preparation refuses version mutation |
| GitHub auth/API/permission error | CI fails closed; never interpret as “Release absent” |
| Source changes while release build runs | Refuse the release commit |
| Tag does not equal source version or is outside `origin/master` | CI fails before Release mutation |
| Existing draft Release | Replace only draft assets, verify exact names, then publish |
| Existing published Release | Fail without replacing assets |
| Tag pushed with wrong source/artifact | Do not move the Tag; issue a new patch version |

## 5. Good / Base / Bad Cases

- Good: from clean synchronized `master`, run `scripts/release.sh patch`, `minor`, or `major`, review the version diff and local annotated Tag, then atomically push commit and Tag.
- Base: run `scripts/build-release.sh --skip-tests --output dist-local` for local packaging iteration; do not use this path for Tag publication.
- Bad: manually edit only one build configuration, reuse a published Tag, overwrite a published asset, publish a DMG whose layout or mounted App was not verified, delete a workspace while its owned image is still attached, or treat a GitHub API failure as a missing Release.

## 6. Tests Required

For release workflow changes, run and assert:

```bash
bash -n scripts/build-release.sh scripts/ci-build-release.sh scripts/release.sh tests/test_release_scripts.sh
python3 tests/test_project_version.py
python3 tests/test_ci_signing.py
bash tests/test_release_scripts.sh
scripts/build-release.sh
```

Credential lifecycle tests must prove missing secrets fail before import, authentication/import/build failure cleans up, search-list paths with spaces survive restoration, cleanup failure blocks publication, and raw secrets are removed from the child build environment. Notarization mocks must cover rejected/pending/invalid responses, signing identity/team/runtime/timestamp mismatch, stapling/Gatekeeper failure and checksum-after-stapling order.

Fixture tests must use local `codesign`, `hdiutil`, and `osascript` mocks (never a real certificate) and cover the complete-bundle signing command; DMG creation/layout/conversion; attach plist parsing; exact visible contents and `/Applications` symlink; mounted-App metadata, architectures, and signature; detach and checksum failures; no-overwrite and partial-publication cleanup. Every failure must leave no final-named DMG/checksum pair, and failures after attachment must prove the owned image is detached or its workspace is retained.

The full build must prove unit tests pass, bundle version/build/identifier match source, both architectures exist, the original and DMG-mounted Apps pass strict Bundle signature verification and metadata inspection, `hdiutil verify` succeeds, the Finder `.DS_Store` and approved two-icon layout exist, the `/Applications` symlink is exact, and the checksum verifies. Parse workflow YAML and syntax-check every shell `run` block; run `shellcheck` and `actionlint` when installed.

Before the first production Tag, rehearse in a disposable repository and prove draft retry, published-release rejection, and build-failure behavior. Validate the downloaded app on Apple Silicon and Intel hardware when available.

## 7. Wrong vs Correct

### Wrong

```bash
# Moves an already published Tag and lets CI generate another build number.
git tag -f v0.2.0
git push --force origin v0.2.0
CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER" xcodebuild build
```

### Correct

```bash
# Version and build number are committed, and commit plus immutable Tag move together.
scripts/release.sh minor --push
# Internally: git push --atomic origin HEAD refs/tags/vX.Y.Z
```

For DMG packaging, do not create a compressed image and publish it without a verification mount:

```bash
# Wrong: layout, symlink, and mounted Bundle are unverified.
hdiutil create -srcfolder "$dmg_root" -format UDZO "$final_dmg"

# Correct: configure a writable image, detach, convert, verify, mount read-only,
# validate contents and the mounted App, detach, checksum, then publish.
hdiutil create -srcfolder "$dmg_root" -format UDRW "$writable_dmg"
hdiutil attach -plist -mountpoint "$owned_layout_mount" "$writable_dmg"
# Persist Finder layout, detach, convert to UDZO, then perform an owned read-only verification mount.
```

If source or artifacts are wrong after publication, increment to a new patch release rather than moving the old Tag or replacing its assets.

## 8. Credential contract

The CI wrapper requires `APPLE_CERTIFICATE_P12_BASE64` (certificate plus private key), `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY` (complete Developer ID Application identity), `APPLE_TEAM_ID` (ten uppercase alphanumeric characters), `APPLE_ID`, and `APPLE_APP_SPECIFIC_PASSWORD`. It generates its own random keychain password. It passes only `APPLE_SIGNING_IDENTITY`, `APPLE_TEAM_ID`, `APPLE_KEYCHAIN_PATH` and `APPLE_NOTARY_PROFILE` to the formal build. No provisioning profile is needed by current capabilities. Setup and first real release acceptance are documented in `docs/macos-release.md`.

Mock success does not prove real Apple acceptance. Before claiming end-to-end readiness, configure real credentials, obtain accepted notarization, browser-download the final artifact to a clean Mac, and test launch under default Gatekeeper settings and offline ticket availability. Validate external Tokscale process behavior with hardened runtime.
