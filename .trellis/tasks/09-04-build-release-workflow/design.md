# Technical Design: Build and Release Workflow

## 1. Scope and Decision

The first release workflow targets the maintainer's personal use. It produces one unsigned, unnotarized universal macOS ZIP and publishes it through GitHub Releases. The artifact and release notes must clearly state that Gatekeeper may block or warn on first launch.

Developer ID signing, Hardened Runtime, Apple notarization, DMG/PKG packaging, public-user installation UX, and in-app updates are deliberately deferred. They must be added before positioning the release for ordinary public distribution.

This task implements the approved design through repository scripts, project versioning configuration, GitHub Actions, documentation, and validation.

## 2. Current Architecture and Boundaries

- Project: `TokChan.xcodeproj`
- Shared scheme: `TokChan`
- Product: `TokChan.app`
- Configuration: `Release`
- Deployment target: macOS 13
- Expected architectures: `arm64` and `x86_64`
- Bundle identifier: `com.youranreus.TokChan`
- Version source: `MARKETING_VERSION` in the app target build settings
- Build number source: `CURRENT_PROJECT_VERSION` in the app target build settings
- Tag contract: `v<MARKETING_VERSION>`, for example `v0.1.1`

The workflow has three boundaries:

1. `scripts/build-release.sh` owns testing, deterministic build paths, bundle validation, ZIP creation, checksum generation, and unsigned-distribution warnings.
2. `scripts/release.sh patch` owns local version mutation, release commit, annotated Tag creation, and optional atomic push.
3. `.github/workflows/release.yml` owns Tag validation, invocation of the same build script, draft Release creation, asset upload, and final publication.

CI must call the local build script rather than duplicate its build and packaging commands.

## 3. Local Build Contract

### Interface

```text
scripts/build-release.sh [--output <directory>] [--skip-tests]
```

Defaults:

- configuration: `Release`
- output: repository-root `dist/`
- tests: enabled
- signing mode: unsigned

`--skip-tests` is permitted for local iteration only. The GitHub workflow must never use it.

### Processing

1. Resolve and change to the repository root.
2. Require `xcodebuild`, `xcrun`, `ditto`, `lipo`, and `shasum`.
3. Print macOS and Xcode versions.
4. Read Release and Debug build settings and reject mismatched `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` values.
5. Run only the unit-test bundle with `-only-testing:TokChanTests`; UI tests are not a first-release gate because hosted-runner GUI behavior is less stable.
6. Build `TokChan.app` with a temporary DerivedData path, generic macOS destination, `Release`, `ARCHS='arm64 x86_64'`, `ONLY_ACTIVE_ARCH=NO`, and an explicitly unsigned configuration that does not depend on a login keychain or development team.
7. Validate the built bundle before packaging.
8. Package with `ditto -c -k --keepParent`.
9. Generate a checksum containing the ZIP basename in the canonical form `<sha256>  TokChan-vX.Y.Z-macos-universal.zip`.
10. Reject pre-existing final asset names, stage the ZIP and checksum together, then publish the pair into the output directory without mixing assets from different runs. If the platform cannot swap the pair atomically, move the checksum only after the ZIP and remove the just-created ZIP if the checksum move fails. Cleanup must never delete files that predated the run.

The implementation should prefer a normal Release build for the unsigned first phase. Archive/export remains the future Developer ID boundary because unsigned distribution does not need an export archive.

### Output

```text
dist/TokChan-vX.Y.Z-macos-universal.zip
dist/TokChan-vX.Y.Z-macos-universal.zip.sha256
```

Temporary DerivedData and partial files live outside `dist/` and are removed on exit. Build logs must identify their retained location on failure.

### Required Validation

- `CFBundleShortVersionString` equals `MARKETING_VERSION`.
- `CFBundleVersion` equals `CURRENT_PROJECT_VERSION`.
- `CFBundleIdentifier` equals `com.youranreus.TokChan`.
- The main executable contains both `arm64` and `x86_64` according to `lipo -archs`.
- `unzip -t` succeeds.
- Recomputing SHA-256 matches the checksum file.
- Output states that the app is not Developer ID signed or notarized; a successful build must not be described as publicly distributable.

Any failed command or validation exits non-zero and leaves no final-named ZIP in `dist/`.

## 4. Version and Tag Contract

### Version Model

- `MARKETING_VERSION` uses stable SemVer `X.Y.Z` without a prefix.
- `CURRENT_PROJECT_VERSION` is a positive integer and increments once per release.
- Git Tags use the exact form `vX.Y.Z` and must equal `v${MARKETING_VERSION}`.
- The version is committed in source. CI must not inject a different version or derive the build number from `github.run_number`.

The implementation should enable and verify Apple Generic Versioning, then use `xcrun agvtool` to update both configurations. If the pinned Xcode cannot safely update this project format, implementation must stop and replace this with a tested structured edit; unrestricted regex replacement of the project file is not acceptable.

Implementation verification on Xcode 26.6 (build 17F113) found that `agvtool new-version -all` updates both `CURRENT_PROJECT_VERSION` settings, but `agvtool new-marketing-version` reports generated Info.plist paths as `YES` and leaves both `MARKETING_VERSION` settings unchanged, including after `VERSIONING_SYSTEM = apple-generic` is enabled. The implemented fallback is therefore `scripts/lib/project-version.py`: it recognizes only the two Debug/Release `XCBuildConfiguration` blocks carrying the exact TokChan bundle identifier, requires one version/build/generic-versioning setting in each, rejects drift, performs bounded per-block edits, and round-trips the result. `release.sh` never performs unrestricted project-file replacement.

### `scripts/release.sh patch`

Preconditions:

- working tree and index are clean;
- current branch is `master`;
- `origin/master` exists and current HEAD equals it after `git fetch origin --tags`;
- current marketing version is stable SemVer;
- current build number is a positive integer;
- no local or remote Tag and no GitHub Release exists for the target version;
- `gh` is installed and authenticated for the repository. API unavailability, authentication failure, or insufficient permission must fail closed and must not be interpreted as “Release not found.”

Transaction:

1. Compute `X.Y.(Z+1)` and build number `N+1`.
2. Update both version settings.
3. Re-read build settings and reject drift.
4. Invoke `scripts/build-release.sh` with tests enabled.
5. Display the version diff and request explicit confirmation.
6. Commit only the authoritative version file as `chore(release): vX.Y.Z`.
7. Create annotated Tag `vX.Y.Z` with message `TokChan vX.Y.Z`.
8. Without `--push`, stop locally and print the exact push command.
9. With `--push`, run `git push --atomic origin HEAD refs/tags/vX.Y.Z` after warning that it triggers publication.

The script must not silently reset version edits on failure. Before a Tag is pushed, it may print targeted recovery commands. A pushed Tag is immutable: source fixes require a new patch version; infrastructure-only failures may rerun the same workflow.

## 5. GitHub Actions Contract

### Trigger and Security

- Trigger only on pushed Tags matching the GitHub glob `v[0-9]+.[0-9]+.[0-9]+`.
- Revalidate with strict regex `^v[0-9]+\.[0-9]+\.[0-9]+$` inside the job because GitHub filters are globs.
- Require Tag version to equal Release `MARKETING_VERSION`.
- Require the tagged commit to be reachable from `origin/master`.
- Set workflow permissions to `contents: write` and grant no unnecessary permissions.
- Use the ephemeral `GITHUB_TOKEN`; no personal access token is needed.
- Use `concurrency.group: release-${{ github.ref }}` and `cancel-in-progress: false`.
- Pin third-party actions to audited full commit SHAs during implementation.
- Recommend a repository tag ruleset limiting creation, update, and deletion of `v*` Tags to maintainers.

### Runner and Build Shape

Use one fixed macOS runner job and one pinned/selected Xcode 26 toolchain. Do not use a CPU matrix: the job must generate one universal app. The implementation must verify the exact currently available runner label before merging, prefer a fixed label over `macos-latest`, and log `sw_vers`, `uname -m`, and `xcodebuild -version`.

The implementation uses the fixed `macos-26` runner label and selects an installed `Xcode_26*.app`, then rejects a toolchain whose reported major version is not 26. This accommodates GitHub-hosted Xcode patch refreshes while holding the project-format and OS major boundary fixed. Local implementation validation used Xcode 26.6.

The job invokes `scripts/build-release.sh` without `--skip-tests`, then verifies the two expected asset names.

### Release State Machine

1. If no Release exists for the Tag, create a draft with `gh release create --verify-tag --draft --generate-notes`.
2. Include a prominent note that the asset is unsigned/unnotarized and intended for personal use, so Gatekeeper may block it.
3. If a draft already exists, treat it as an infrastructure retry and upload the two fixed assets with `--clobber`.
4. If a published Release already exists, fail without replacing assets.
5. Verify exact asset names and count after upload.
6. Publish only after all checks succeed by changing `draft` to false.

The workflow must not delete or move a remote Tag and must not overwrite a published asset. Optional workflow artifacts may retain build output and logs for a bounded period, but GitHub Release remains the user-facing channel.

## 6. Credentials and Distribution Safety

The personal-use first phase requires no Developer ID or Apple notarization secrets. It only requires repository Actions to permit `contents: write` for `GITHUB_TOKEN`.

The release must never imply Apple verification. Documentation should explain that unsigned downloads can trigger Gatekeeper and should provide the SHA-256 verification command. It should not normalize broad security bypasses as a public installation method.

Before public distribution, a separate hardening task must cover:

- Apple Developer Program ownership;
- Developer ID Application certificate import through a temporary keychain;
- Hardened Runtime compatibility testing;
- archive and Developer ID export;
- App Store Connect API-key notarization;
- `stapler` and `spctl` validation;
- certificate rotation and incident response.

## 7. Failure Recovery and Rollback

| Failure point | Recovery |
| --- | --- |
| Version changed, no commit | Inspect diff, correct or restore only the project file, then rerun |
| Release commit exists, local Tag absent | Rerun validation, then create the Tag |
| Local Tag exists, not pushed | Delete the local Tag, correct source, and recreate it |
| Tag pushed, build/test infrastructure fails | Rerun the same workflow only if source and intended assets are unchanged |
| Tag pushed, source or artifact is wrong | Do not move the Tag; release a new patch |
| Draft exists with partial assets | Rerun; replace only draft assets, verify, then publish |
| Published Release exists | Fail closed; do not overwrite assets |
| Incorrect binary was published | Mark/remove the bad Release manually as policy permits and issue a new patch; never decrement versions |

Rollback uses a new patch version rather than moving published Tags or replacing published assets.

## 8. Trade-offs

- ZIP is chosen over DMG because `ditto` provides a low-maintenance app-bundle package and checksum flow. A branded installer is unnecessary for personal use.
- One universal binary is chosen over an architecture matrix to keep installation and Release state atomic.
- Source-controlled versions are chosen over CI-generated versions so About UI, source, Tag, and artifact remain reproducible.
- Draft-first publication adds one state transition but prevents users from seeing incomplete Releases and makes infrastructure retries safe.
- Unsigned publication minimizes initial credentials and configuration but is explicitly limited to personal use because Gatekeeper UX is unsuitable for a general audience.
