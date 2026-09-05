# TokChan

TokChan is a compact native macOS menu-bar companion for [Tokscale](https://tokscale.ai). It shows Tokscale all-time, daily, trailing-week, and trailing-month totals plus client/model detail and manages Tokscale's built-in autosubmit through its official CLI.

## Requirements

- macOS 13 or later
- Xcode 26 (the project uses Xcode 26 project format)
- Node.js with an executable `npx`
- An existing Tokscale login for submission and autosubmit operations

## Run

Open `TokChan.xcodeproj` and run the `TokChan` scheme, or build from the repository root:

```bash
xcodebuild -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' build
```

TokChan is an agent-style app, so it appears in the menu bar and does not create a Dock icon. The first panel load discovers the current Tokscale username with `whoami` when no override is saved.

## Build a personal-use release

The shared release entry point runs `TokChanTests`, performs a credential-free Release build for both Apple Silicon and Intel, validates its metadata and architectures, ad-hoc signs and strictly verifies the complete app bundle, then creates and re-verifies a native drag-to-install DMG plus SHA-256 checksum:

```bash
scripts/build-release.sh
# Local iteration only; never use this for a Tag release:
scripts/build-release.sh --skip-tests --output dist-local
```

The default assets are:

```text
dist/TokChan-vX.Y.Z-macos-universal.dmg
dist/TokChan-vX.Y.Z-macos-universal.dmg.sha256
```

Existing final-named assets are never overwritten. Verify a downloaded pair from the directory containing both files with:

```bash
shasum -a 256 -c TokChan-vX.Y.Z-macos-universal.dmg.sha256
hdiutil verify TokChan-vX.Y.Z-macos-universal.dmg
```

To install, open the DMG and drag `TokChan.app` onto the `Applications` folder shown beside it, then eject the `TokChan` volume. Do not replace an existing installed copy unless that is intentional.

> **Warning:** the packaged app bundle has a complete ad-hoc signature, but it is not Developer ID signed and is not Apple-notarized. DMG packaging improves installation convenience only. Ad-hoc signing lets macOS verify bundle integrity and its designated identifier; it does not establish an Apple-verified developer identity or guarantee Gatekeeper acceptance for downloads. This format is intended only for the maintainer's personal use. Gatekeeper may block or warn on first launch, and the artifact is not suitable for ordinary public distribution.

## Prepare and publish a release

Versions are source-controlled in `TokChan.xcodeproj/project.pbxproj`. The app uses stable `X.Y.Z` marketing versions, positive integer build numbers, and annotated Tags named exactly `vX.Y.Z`.

Start from a clean `master` checkout whose `HEAD` exactly matches `origin/master`. Local release preparation requires only Git and Python:

```bash
scripts/release.sh patch
scripts/release.sh minor
scripts/release.sh major
```

Choose `patch` for `X.Y.(Z+1)`, `minor` for `X.(Y+1).0`, or `major` for `(X+1).0.0`. The command fetches Tags, checks local/remote Tag availability, increments the build number, runs the complete release build, shows the project diff, and asks before creating `chore(release): vX.Y.Z` plus its annotated Tag. By default it does not push. After review, use the exact atomic push command printed by the script, or add `--push` to any release type for a second push confirmation:

```bash
scripts/release.sh patch --push
```

Pushing the Tag triggers `.github/workflows/release.yml`. The workflow validates the Tag against the project version and `origin/master`, runs the same tested build script, creates or resumes a draft GitHub Release, verifies its exact two assets, and only then publishes it. A published Release is immutable to the workflow; source or artifact corrections require a new patch version. Infrastructure-only failures may rerun the same workflow while its Release remains a draft.

### GitHub repository setup

- In **Settings → Actions → General**, allow workflows effective read/write access so the ephemeral `GITHUB_TOKEN` can receive `contents: write`. No personal access token, Apple certificate, or other private signing credential is used by this personal-use workflow.
- Add a Tag ruleset for `v*` that limits Tag creation, update, and deletion to maintainers. Published Tags must never be moved.
- Consider GitHub immutable Releases after rehearsing the workflow in a disposable repository.

Before distributing TokChan to ordinary users, complete a separate hardening effort covering Developer ID Application signing, Hardened Runtime compatibility, Xcode archive/export, App Store Connect API-key notarization, stapling, `spctl`/Gatekeeper validation, credential rotation, incident recovery, and in-app updates. PKG distribution remains outside this personal-use release flow.

## Integration behavior

- The panel keeps statistics fixed while the client list scrolls. Each client starts with its top five models and can expand; client logos ship in the app.
- Period tabs use Tokscale’s own range boundaries and five-category Tokens breakdown. Daily usage comes from the server’s end-date contribution bucket; daily rank is unavailable.
- Opening the panel only reads the public profile and `autosubmit status --json`.
- All scope snapshots and the selected tab are cached in a local JSON file. Reopening or switching to a cached scope does not fetch again; submit/refresh updates the selected scope.
- Refresh runs `submit` first, then reloads the public profile.
- Autosubmit status and “Run now” appear in Settings. Settings apply autosubmit changes through `enable` or `disable`; “Run now” uses `autosubmit run --force`.
- Every command uses `npx --yes tokscale@<configured-version>` with an argument array, without shell interpolation.
- TokChan stores only username, package version, and an optional absolute `npx` path. Tokscale remains the source of truth for credentials and autosubmit state.

The app intentionally does not enable App Sandbox because Tokscale needs local client-data access and manages its own macOS LaunchAgent.
