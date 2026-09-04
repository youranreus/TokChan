# Implementation Plan: Build and Release Workflow

> Execute this checklist in order under the approved implementation phase.

## 1. Prepare the Project Version Contract

- [x] Verify the exact Xcode version required by `objectVersion = 77` and update the documented minimum if Xcode 15 cannot open/build it.
- [x] Enable Apple Generic Versioning for the TokChan app target if required by `agvtool`.
- [x] Probe `xcrun agvtool` against a project copy; Xcode 26.6 updates both build-number settings but fails to update generated-Info.plist marketing versions, so it is not used for mutation.
- [x] Introduce the narrowly scoped, tested `scripts/lib/project-version.py` project-setting editor instead of global text replacement.
- [x] Add `dist/` and other generated release directories to `.gitignore`.

Rollback point: revert only project-versioning configuration and ignore-file changes before adding scripts.

## 2. Implement the Shared Build Script

Create `scripts/build-release.sh` with the contract from `design.md`:

- [x] Parse `--output` and `--skip-tests`; reject unknown or duplicate arguments.
- [x] Resolve repository root independently of caller working directory.
- [x] Add strict shell mode, command checks, temporary directories, cleanup trap, and actionable failure messages.
- [x] Read and compare Debug/Release marketing versions and build numbers.
- [x] Run `TokChanTests` unless explicitly skipped.
- [x] Build unsigned Release output with deterministic temporary DerivedData and explicit universal architecture settings.
- [x] Validate bundle identifier, versions, and both executable architectures.
- [x] Package `TokChan.app` with `ditto`, validate the ZIP, and generate a basename-only SHA-256 checksum compatible with `shasum -c`.
- [x] Reject pre-existing final assets; stage and publish ZIP/checksum as one pair, cleaning up only files created by the current run if the second move fails.
- [x] Print the unsigned/unnotarized warning after successful publication.
- [x] Add shell-level tests for argument parsing, invalid version/configuration drift, stale/partial output cleanup, and artifact naming where practical.

Rollback point: the script is additive; remove it and generated ignored output without touching Xcode project behavior.

## 3. Implement the Local Patch Release Script

Create `scripts/release.sh`:

- [x] Support exactly `patch` plus optional `--push`.
- [x] Require a clean tree, `master`, synchronized `origin/master`, and fetched Tags.
- [x] Parse stable SemVer and positive integer build number.
- [x] Compute patch and build-number increments.
- [x] Require an installed and authenticated `gh`; distinguish a confirmed missing Release from API, network, authentication, or permission errors and fail closed on the latter.
- [x] Check that the target Tag and Release do not exist locally or remotely.
- [x] Update versions through the mechanism proven in Step 1 and verify both configurations.
- [x] Invoke `scripts/build-release.sh` with tests enabled.
- [x] Show the exact project diff and require confirmation before creating Git objects.
- [x] Commit only the project version file with `chore(release): vX.Y.Z`.
- [x] Create an annotated Tag and, only with `--push`, atomically push HEAD and Tag.
- [x] Print recovery instructions for each pre-push failure state without destructive automatic reset.
- [x] Add tests for SemVer patching, dirty/synchronized-tree guards, duplicate Tag rejection, and dry local Tag flow using a temporary Git remote.

Rollback point: before push, remove the local Tag and revert/reset the dedicated version commit as appropriate. After push, never move the Tag; release a new patch.

## 4. Implement the Tag Release Workflow

Create `.github/workflows/release.yml`:

- [x] Confirm the available fixed macOS runner and Xcode 26 selector immediately before implementation; record versions in logs.
- [x] Trigger on `vX.Y.Z`-shaped Tags, then strictly validate regex, project version equality, and reachability from `origin/master`.
- [x] Configure `contents: write`, same-Tag concurrency, and no unnecessary permissions.
- [x] Pin external actions to reviewed full commit SHAs.
- [x] Invoke `scripts/build-release.sh` with tests enabled.
- [x] Verify exact ZIP and checksum names before any Release mutation.
- [x] Implement the absent/draft/published state checks with GitHub CLI.
- [x] Create or reuse a draft, upload/replace draft assets, verify assets, then publish.
- [x] Fail closed when a published Release already exists.
- [x] Include personal-use, unsigned/unnotarized, and Gatekeeper warnings in Release notes.
- [x] Retain build/log artifacts for a bounded diagnostic period if useful.

Rollback point: disable the workflow or remove an incomplete draft. Do not delete/move a published Tag or overwrite published assets.

## 5. Documentation and Repository Configuration

- [x] Update README with local build, local patch release, optional push, artifact verification, and unsigned personal-use limitations.
- [x] Document repository requirement: Actions `GITHUB_TOKEN` must have effective `contents: write` access.
- [x] Document recommended `v*` Tag ruleset and who may create/delete Tags.
- [x] Add a clear future-public-release checklist for Developer ID, Hardened Runtime, notarization, and Gatekeeper validation.

## 6. Validation Commands

Run from a clean checkout:

```bash
# Repository and project metadata
xcodebuild -version
xcodebuild -list -project TokChan.xcodeproj
xcodebuild -project TokChan.xcodeproj -scheme TokChan -configuration Debug -showBuildSettings \
  | grep -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION'
xcodebuild -project TokChan.xcodeproj -scheme TokChan -configuration Release -showBuildSettings \
  | grep -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|ARCHS|CODE_SIGN'

# Script syntax/static checks
bash -n scripts/build-release.sh scripts/release.sh
# Run shellcheck if adopted/available
shellcheck scripts/build-release.sh scripts/release.sh

# Tests and local package
xcodebuild test -project TokChan.xcodeproj -scheme TokChan \
  -destination 'platform=macOS' -only-testing:TokChanTests
scripts/build-release.sh
unzip -t dist/TokChan-vX.Y.Z-macos-universal.zip
shasum -a 256 -c dist/TokChan-vX.Y.Z-macos-universal.zip.sha256

# Inspect packaged bundle after extracting to a temporary directory
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' TokChan.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' TokChan.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' TokChan.app/Contents/Info.plist
lipo -archs TokChan.app/Contents/MacOS/TokChan

# Workflow lint if actionlint is adopted/available
actionlint .github/workflows/release.yml
```

Release rehearsal:

- [ ] Use a disposable repository with a valid stable `vX.Y.Z` Tag matching its project version to exercise the complete workflow without consuming a production version.
- [ ] Prove build failure leaves no published Release.
- [ ] Prove partial draft upload can be rerun and recovered.
- [ ] Prove rerunning after publication fails without replacing assets.
- [ ] Download the Release ZIP on both Apple Silicon and Intel macOS where available; verify checksum, unzip, and launch behavior including the expected Gatekeeper warning.

## 7. Review Gates Before Merge

- [x] Trellis spec-compliance review, available static checks, unit tests, packaging validation, and workflow review pass.
- [x] No certificate, private key, Apple credential, PAT, or local path is committed.
- [x] Local and CI builds use the same build script.
- [x] About version, source version, Tag, filename, and Release name agree.
- [x] UI tests remain explicitly deferred rather than silently skipped.
- [x] Documentation never presents the unsigned artifact as suitable for general public distribution.
- [x] Public distribution is documented as a separate future effort requiring Developer ID signing and notarization.

`shellcheck` and `actionlint` were unavailable locally; shell syntax checks, Python tests, script integration tests, YAML parsing, workflow run-block syntax checks, and a full release build were used instead. The disposable-repository and two-architecture-machine rehearsals above remain operational pre-production checks and do not change the repository implementation.

## 8. Delivery Status

The approved implementation was completed in this task as one integrated change because the scripts, Tag contract, workflow, and documentation share one release boundary. The remaining rehearsal items require external GitHub state or additional physical hardware and must be completed before treating the workflow as production-proven.
