# Build, Self-Update, and Release Workflow

## 1. Scope / Trigger

Use this contract whenever changing TokChan's Sparkle integration, version settings, nested signing, release packaging, Git Tags, GitHub Release/Pages publication, or `.github/workflows/release.yml`.

Official GitHub Releases contain one universal drag-to-install DMG, its SHA-256 checksum, and one Sparkle update ZIP. CI requires Developer ID Application signing, Apple notarization, and stapled tickets for both app and DMG; the ZIP must contain that same signed, notarized, stapled app and be authenticated by the appcast's Sparkle EdDSA signature. Credential-free local builds retain ad-hoc signing for iteration and must not be uploaded as official assets. Historical published releases remain immutable.

## 2. Signatures

Local commands:

```text
scripts/build-release.sh [--output <directory>] [--skip-tests] [--notarize]
scripts/ci-build-release.sh
scripts/release.sh {patch|minor|major} [--push]
python3 scripts/lib/project-version.py <project.pbxproj> get
python3 scripts/lib/project-version.py <project.pbxproj> set --marketing X.Y.Z --build N
```

Release assets and public feed:

```text
TokChan-vX.Y.Z-macos-universal.dmg
TokChan-vX.Y.Z-macos-universal.dmg.sha256
TokChan-vX.Y.Z-macos-universal.zip
https://youranreus.github.io/TokChan/appcast.xml
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
- Xcode compilation remains credential-free with automatic signing disabled. Explicit `--notarize` signs every nested code object and the outer app with Developer ID Application, `--options runtime`, and `--timestamp`; default local mode signs the same graph with `--sign -`. Never use signing-time `--deep` to hide nested-code ordering problems. Do not add broad hardened-runtime exception entitlements without evidence.
- Sign inside-out. For the pinned Sparkle 2 layout, sign `Sparkle.framework/Versions/B/Autoupdate`, `Sparkle.framework/Versions/B/Updater.app`, `Sparkle.framework/Versions/B/XPCServices/Downloader.xpc`, and `Sparkle.framework/Versions/B/XPCServices/Installer.xpc` before `Sparkle.framework`, then sign `TokChan.app` last. Sibling leaf order is immaterial; parent-before-child is forbidden because a later child signature invalidates the parent's resource seal. Inventory the actual embedded bundle on every Sparkle upgrade and fail on missing or unexpected signable code instead of assuming the old graph. Preserve and verify each component's identifier, designated requirements, flags, and entitlements (including Autoupdate's application identifier); only the outer app receives `com.youranreus.TokChan` explicitly.
- The built executable must contain `arm64` and `x86_64`; bundle identifier must be `com.youranreus.TokChan`.
- Before packaging, strict `codesign --verify --deep --strict --verbose=2` verification and `codesign -dv --verbose=4` inspection must prove the expected designated identifier, the selected signature mode, Info.plist coverage, and sealed resources. Official mode additionally requires the expected Developer ID authority, Team ID, secure timestamp, and hardened runtime.
- DMG staging contains `TokChan.app` plus an `Applications` symbolic link whose target is exactly `/Applications`. The image uses a writable HFS+ layout phase followed by compressed read-only UDZO conversion; no third-party packaging dependency or committed `.DS_Store` template is allowed.
- Finder layout automation must persist `.DS_Store` metadata for icon view, a fixed compact window, hidden toolbar/status bar, and App-left/Applications-right icon positions. Layout failure is fatal and no custom background is used.
- `hdiutil attach -plist` output must be parsed structurally. Every image mounts at a current-run owned path, auto-open is disabled for verification, and every tracked attachment must detach before temporary workspace deletion.
- Before publication, `hdiutil verify` must pass. The compressed DMG is then mounted read-only and must expose only `TokChan.app` and `Applications` as user-visible root entries; the mounted App must pass version, build, identifier, architecture, strict signature, and signature-metadata verification.
- Official mode submits a temporary ZIP of the fully signed app, requires notarization `Accepted`, then staples and validates the app before any distribution archive is staged. Sign the compressed DMG, require its own accepted notarization, staple and validate it, then verify the DMG and mounted app (including stapled app ticket and Gatekeeper assessment). Any failure is fatal.
- Create the Sparkle update ZIP only after app stapling and validation, using `ditto -c -k --sequesterRsrc --keepParent`. It contains exactly one functional top-level `TokChan.app`; `__MACOSX` metadata may only mirror that app. Extract it to an owned temporary directory and re-run bundle version/build/identifier, architecture, strict nested signature, Developer ID metadata, and stapled-ticket checks. The app in the ZIP and DMG must derive from the same post-stapling app path.
- Generate the DMG checksum only after DMG signing and stapling have finished; it records the DMG basename so `shasum -a 256 -c` works after download. Sparkle's EdDSA enclosure signature authenticates the ZIP; the DMG checksum is not the updater trust root.
- Final local assets are never overwritten. One publication lock serializes the final three-file set, and cleanup removes only resources owned by the current run.
- Cleanup removes only resources owned by the current run. If an owned image cannot be detached, fail and retain the workspace rather than deleting a live mount point; partial final publication removes only the files marked as created by that run.
- The Actions workflow uses the platform token through `GH_TOKEN: ${{ github.token }}` and declares only `contents: write`, `pages: write`, and `id-token: write`. Pin every action to a reviewed, immutable lowercase 40-character commit SHA and place the exact reviewed release version beside it (for example, `# v4.0.5`, not only `# v4`). A syntactically valid SHA is insufficient: a nonexistent commit makes Actions fail during job setup, before checkout or any workflow step runs. Keep same-Tag concurrency with cancellation disabled, deploy the production feed through the `github-pages` environment, and expose the deployment step's `page_url`; do not add pull-request or untrusted-fork release triggers.
- Required repository Secrets are `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_TEAM_ID`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `SPARKLE_PRIVATE_KEY_BASE64`. Required repository Variable `SPARKLE_PUBLIC_ED_KEY` is public key material, not a Secret. `GITHUB_TOKEN`/`github.token`, `GITHUB_REPOSITORY`, `GITHUB_REF_NAME`, `GITHUB_REF_TYPE`, `GITHUB_SHA`, `GITHUB_ACTIONS`, and `RUNNER_TEMP` are Actions-provided and must not be manually duplicated. The workflow must validate every required value before the first mutation.
- `scripts/ci-build-release.sh` imports the P12 into an owned temporary keychain, stores notary credentials, invokes `--notarize`, then restores the search list and deletes credentials on success or failure. Pass `APPLE_SIGNING_IDENTITY`, `APPLE_TEAM_ID`, `APPLE_KEYCHAIN_PATH`, `APPLE_NOTARY_PROFILE`, and the non-secret `SPARKLE_PUBLIC_ED_KEY` to the formal build; remove raw Apple certificate/password/notary secrets first. No private key, certificate, or password is committed or logged. Restore the caller umask before building so the private credential-file policy does not produce inaccessible app resources. Cleanup failure fails CI before publication. Apple submission/verification diagnostics must remain visible in failed Actions logs; a runner-local path alone is insufficient.
- GitHub Release publication is `absent -> draft -> exact three-asset set -> published`. A draft may be resumed; a published Release and its assets are never overwritten.
- Build and validate a candidate appcast privately before Release mutation, but make it discoverable only in this order: upload all three assets to the draft; verify exact names and downloadable bytes; publish the stable non-prerelease Release; upload a Pages artifact containing only public feed files; deploy `appcast.xml` last. Generation order is not publication order. Never expose a feed entry while its enclosure URL is draft-only, absent, or returns different bytes.
- Preserve the prior appcast when adding an item. A verified first-feed 404 may bootstrap an empty feed; TLS, timeout, rate-limit, 5xx, malformed XML, wrong repository, or unknown fetch failures must fail closed rather than silently replace feed history. The candidate item uses `CFBundleVersion` as `sparkle:version`, `MARKETING_VERSION` as `sparkle:shortVersionString`, the exact ZIP byte length, a nonempty `sparkle:edSignature`, and HTTPS enclosure/release-notes URLs for the same stable Tag. Drafts, prereleases, and non-`vX.Y.Z` Tags never enter the stable feed.
- Pages deployment is the sole discovery commit point. Delete the decoded private key and copied ZIP before assembling/uploading the Pages artifact, and reject symlinks, hidden credential files, or any content other than the intended public feed/release-note files. A failure before deployment leaves the previous feed active. A failure after Release publication must use a feed-only recovery that regenerates and validates the candidate from immutable published assets; it must not clobber or republish the Release.
- Official release notes must state Developer ID signing, Apple notarization, stapled app/DMG tickets, checksum guidance, and normal Internet-download confirmation. Reject drafts missing the new notes or retaining obsolete unsigned-distribution claims; published releases are untouched. Local ad-hoc output must still clearly disclose its limits. Never promise to disable OS verification or guarantee no first-launch prompt.

## 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Debug/Release version drift | Fail before tests or packaging |
| Invalid SemVer or non-positive build | Fail without editing or publishing assets |
| Existing final asset or foreign publication lock | Fail the entire three-file publication without deleting or replacing the existing resource |
| Missing/invalid signing credentials, signing identity/team mismatch, missing runtime/timestamp, rejected/pending/timed-out notarization, failed stapling or Gatekeeper assessment | Fail before publication without unsigned fallback |
| Missing/unexpected Sparkle nested code, parent signed before child, or any nested identifier/authority/team/runtime/timestamp/strict verification mismatch | Fail before notarization and archive creation; never compensate with `codesign --deep --force` |
| DMG/ZIP creation, Finder layout, attach/plist parsing, detach, conversion, archive/image/content validation, metadata, architecture, signing, strict signature inspection, or checksum failure | Fail and leave no final-named new asset; retain the workspace if a live owned mount cannot be detached |
| Dirty tree, non-`master`, or `HEAD != origin/master` | Refuse release preparation |
| Local or remote Tag already exists | Local preparation refuses version mutation |
| GitHub auth/API/permission error | CI fails closed; never interpret as “Release absent” |
| Action pin is not a reviewed full SHA, has an inexact version comment, or names a nonexistent upstream commit | Offline tests reject pins outside the reviewed allowlist; upstream existence/tag mismatch blocks the pin change. A nonexistent 40-character SHA otherwise fails Actions during job setup before checkout |
| Apple credential Secret, Sparkle private-key Secret, Sparkle public-key Variable, Pages permission, or `github-pages` environment missing/invalid | Fail before the corresponding build/publication mutation; never fall back to unsigned ZIP or an unsigned feed |
| Existing appcast fetch returns verified first-feed 404 | Bootstrap a new feed from the current stable item |
| Existing appcast fetch has TLS/network/5xx/rate-limit/malformed/wrong-origin failure | Fail closed and leave the deployed feed unchanged |
| Candidate appcast lacks exact build/display version, byte length, HTTPS URL, release notes, or EdDSA signature | Fail before Release publication or Pages upload |
| Release asset upload/publish fails | Keep the Release absent/draft and deployed feed unchanged; a draft retry may replace draft assets |
| Pages upload/deploy fails after Release publication | Keep the prior feed active; recover by redeploying a regenerated candidate from immutable published assets without mutating the Release |
| Source changes while release build runs | Refuse the release commit |
| Tag does not equal source version or is outside `origin/master` | CI fails before Release mutation |
| Existing draft Release | Replace only draft assets, verify the exact three names and bytes, then publish |
| Existing published Release | Fail without replacing assets |
| Tag pushed with wrong source/artifact | Do not move the Tag; issue a new patch version |

## 5. Good / Base / Bad Cases

- Good: from clean synchronized `master`, run `scripts/release.sh patch`, `minor`, or `major`; CI signs nested Sparkle code inside-out, publishes the exact immutable DMG/checksum/ZIP set, and deploys the validated feed last.
- Base: run `scripts/build-release.sh --skip-tests --output dist-local` for local packaging iteration; it may use ad-hoc signatures and an unset development public key, so do not use this path for Tag or feed publication.
- Bad: manually edit only one build configuration, sign only `Sparkle.framework` and the app, reuse a published Tag, overwrite a published asset, publish a DMG/ZIP whose embedded app was not verified, deploy appcast before its ZIP is publicly downloadable, drop feed history after a transient fetch failure, delete a workspace while its owned image is still attached, or treat a GitHub API failure as a missing Release.

## 6. Tests Required

For release workflow changes, run and assert:

```bash
bash -n scripts/build-release.sh scripts/ci-build-release.sh scripts/release.sh tests/test_release_scripts.sh
python3 tests/test_project_version.py
python3 tests/test_ci_signing.py
bash tests/test_release_scripts.sh
scripts/build-release.sh
```

Credential lifecycle tests must prove every required Secret/Variable fails before import or publication when missing; malformed base64/private keys fail closed; authentication/import/build failure cleans up; search-list paths with spaces survive restoration; cleanup failure blocks publication; and raw secrets are absent from the child build environment and Pages artifact. Notarization mocks must cover rejected/pending/invalid responses, signing identity/team/runtime/timestamp mismatch, stapling/Gatekeeper failure, app-stapling-before-ZIP order, and checksum-after-DMG-stapling order.

Fixture tests must use local `codesign`, `hdiutil`, and `osascript` mocks (never a real certificate) and cover the inside-out signing partial order: all four Sparkle leaves precede Sparkle.framework, which precedes TokChan.app; fail when a nested component is missing, extra, signed after its parent, or has wrong metadata. Also cover DMG creation/layout/conversion; ZIP list/extraction and exact top-level app; attach plist parsing; exact DMG contents and `/Applications` symlink; both archived Apps' metadata, architectures, nested signatures, and ticket; detach/checksum failures; no-overwrite and three-file partial-publication cleanup. Every failure must leave no final-named DMG/checksum/ZIP set, and failures after attachment must prove the owned image is detached or its workspace is retained.

Workflow tests must parse YAML and syntax-check every shell `run` block. In the normal offline suite, compare every `uses:` entry against a deterministic reviewed allowlist of exact `(action, lowercase 40-character SHA, full release version comment)` tuples; reject missing, extra, moving-tag, abbreviated-SHA, version-comment, and unreviewed-pin changes without contacting GitHub. Whenever a pin is intentionally changed, separately resolve that action's exact release tag in its authoritative upstream repository (for example, `git ls-remote https://github.com/<owner>/<action>.git 'refs/tags/<exact-version>' 'refs/tags/<exact-version>^{}'`), review the resolved commit, and require the workflow SHA and offline allowlist to match the tag commit (the peeled commit for an annotated tag). This network-backed upstream verification is a pin-review step, not part of every test run. Also assert exact permissions, `github-pages` environment, required Secret/Variable expressions, exact three-asset upload, draft/published immutability, and the order `candidate generated -> assets verified/uploaded -> Release published -> private material absent -> Pages deployed`. Mock appcast bootstrap, history preservation, malformed/failed prior-feed fetch, signing failure, bad/missing enclosure fields, wrong byte length/URL/version, Pages failure, and feed-only recovery; no test may contact GitHub Pages or use a real EdDSA key.

The full build must prove unit tests pass, generated Info.plist update keys are valid, bundle version/build/identifier match source, both architectures exist, and the original, DMG-mounted, and ZIP-extracted Apps pass strict nested Bundle signature verification and metadata inspection. It must also prove `hdiutil verify`, Finder `.DS_Store`, approved two-icon layout, exact `/Applications` symlink, checksum verification, app/DMG stapling, Gatekeeper acceptance, and a candidate appcast whose signature verifies against the embedded public key. Run `shellcheck` and `actionlint` when installed.

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

For nested signing and feed publication:

```bash
# Wrong: signs a parent first, mutates children later, and exposes discovery too early.
codesign --force --sign "$IDENTITY" TokChan.app
codesign --force --deep --sign "$IDENTITY" TokChan.app/Contents/Frameworks/Sparkle.framework
# deploy appcast.xml before the Release ZIP is public

# Correct: sign all leaves, then containers, then app; verify privately and deploy feed last.
codesign --force --sign "$IDENTITY" "$sparkle/Versions/B/Autoupdate"
codesign --force --sign "$IDENTITY" "$sparkle/Versions/B/Updater.app"
codesign --force --sign "$IDENTITY" "$sparkle/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign "$IDENTITY" "$sparkle/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "$IDENTITY" "$sparkle"
codesign --force --sign "$IDENTITY" TokChan.app
# notarize/staple -> archive/verify -> publish exact Release assets -> deploy appcast
```

Production commands add the required keychain, hardened-runtime, and timestamp options shown above. `--deep` remains verification-only.

If source or artifacts are wrong after publication, increment to a new patch release rather than moving the old Tag or replacing its assets. If only feed deployment failed and immutable assets are correct, use feed-only recovery for those exact bytes.

## 8. Credential contract

The CI wrapper requires `APPLE_CERTIFICATE_P12_BASE64` (certificate plus private key), `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY` (complete Developer ID Application identity), `APPLE_TEAM_ID` (ten uppercase alphanumeric characters), `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and non-secret `SPARKLE_PUBLIC_ED_KEY`. It generates its own random keychain password. It removes raw Apple credential values before invoking the formal build and retains only the derived Apple signing context plus the public Sparkle key. The appcast-generation step separately requires `SPARKLE_PRIVATE_KEY_BASE64`; decode it into a mode-0600 owned temporary file, never pass it to Xcode, and delete it before Pages artifact assembly. No provisioning profile is needed by current capabilities. Setup and first real release acceptance are documented in `docs/macos-release.md`.

Mock success does not prove real Apple acceptance. Before claiming end-to-end readiness, configure real credentials, obtain accepted notarization, browser-download the final artifact to a clean Mac, and test launch under default Gatekeeper settings and offline ticket availability. Validate external Tokscale process behavior with hardened runtime.

## 9. Scenario: Manual Sparkle self-update

### 9.1 Scope / Trigger

Use this contract when changing the in-app update entry point, Sparkle package/configuration, updater lifetime, standard update UI, or UI-test substitution. TokChan supports user-initiated stable updates only: no startup, scheduled, background, or prerelease checks.

### 9.2 Signatures

```swift
@MainActor
protocol AppUpdating: AnyObject {
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

@MainActor
final class AppUpdater: ObservableObject, AppUpdating {
    @Published private(set) var canCheckForUpdates: Bool
    static func live() -> AppUpdater
    static func offlineTest(isBusy: Bool = false) -> AppUpdater
}
```

The live adapter owns one long-lived `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)`, calls `controller.checkForUpdates(nil)` for an explicit user request, and observes `controller.updater.canCheckForUpdates` for availability.

### 9.3 Contracts

- The current reviewed Sparkle pin is exactly `2.7.1` in `project.pbxproj` and `Package.resolved`; link the `Sparkle` product only to the app target. A version change triggers nested-code inventory, signing/notarization, package-tool-path, minimum-macOS, license, feed, and end-to-end update review before this recorded pin changes.
- Generated Debug and Release Info.plists contain `SUFeedURL=https://youranreus.github.io/TokChan/appcast.xml`, `SUPublicEDKey=$(SPARKLE_PUBLIC_ED_KEY)`, and `SUEnableAutomaticChecks=NO`. The URL must be HTTPS and stable. An official build requires a nonempty public key that verifies the candidate appcast signature; the matching private key never enters the source tree, Xcode build, app bundle, logs, or UI-test process.
- Construct the live updater once at the application composition root and retain it for the process lifetime. Inject that same observable adapter into Settings; views never instantiate Sparkle controllers or perform feed/download/install work.
- The About tab has one “检查更新” action. It is disabled when `canCheckForUpdates == false`. `checkForUpdates()` guards availability and sets local availability false before forwarding so two synchronous clicks cannot start two drivers; Sparkle's authoritative availability publisher restores state.
- Sparkle's standard user driver owns no-update feedback, release notes, confirmation, download, EdDSA/code-signature validation, installation, relaunch, and recoverable errors. Do not duplicate this state machine or manually replace the installed app.
- Only a `DEBUG` launch containing `--ui-testing` may select `offlineTest`; `--updater-busy` initializes its button-disabled fixture. Release ignores both arguments and always uses the live adapter. Tests and previews must not fetch the production feed or invoke an installer.
- The updater trust chain is HTTPS plus Sparkle EdDSA plus Developer ID code-signature continuity. Apple notarization/stapling and the DMG SHA-256 remain release requirements but do not replace EdDSA. The feed's `sparkle:version` compares positive integer `CFBundleVersion`; `MARKETING_VERSION` is display-only.

### 9.4 Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| `canCheckForUpdates == true` and user clicks | Disable immediately and forward exactly one explicit check to the retained controller |
| Busy/unavailable and user clicks again | Ignore it; never create or queue a second update driver |
| Sparkle publishes availability again | Update button state on the main actor |
| Current feed build `<= CFBundleVersion` | Standard Sparkle window reports no update; no download/install starts |
| Higher stable build with valid metadata/signatures | Standard window shows display version/release notes and waits for user confirmation |
| Feed/network/XML/enclosure/download/EdDSA/code-signature/install/relaunch failure | Let Sparkle show its recoverable error and preserve the current runnable app; re-enable only when Sparkle reports availability |
| Missing/empty/invalid `SUFeedURL` or `SUPublicEDKey` in an official build | Fail build/release validation; do not publish an updater-enabled artifact |
| `--ui-testing` in Debug | Use offline adapter; perform zero network/install work |
| `--ui-testing` or `--updater-busy` in Release | Ignore fixture flags and construct the live adapter |
| Prerelease/draft/non-SemVer feed item | Exclude it during publication; the stable client must not discover it |

### 9.5 Good / Base / Bad Cases

- Good: a user clicks once, the button disables synchronously, Sparkle shows the standard UI, verifies the signed stable ZIP, replaces the app only after confirmation, and reports availability after completion/cancel/failure.
- Base: the feed's latest build is not newer; Sparkle reports that TokChan is current and performs no installation.
- Bad: create a controller inside `SettingsView`, poll or parse appcast in SwiftUI, infer busy state from a custom spinner, permit Release fixture flags, compare only marketing-version strings, or implement download/unzip/copy/relaunch code in TokChan.

### 9.6 Tests Required

- Adapter unit tests: available action forwards once; immediate duplicate is rejected; unavailable action forwards zero; publisher false/true transitions update state; recovery permits one later check; all assertions run on `@MainActor`.
- Composition tests: one retained adapter reaches Settings; Debug UI-test arguments select offline ready/busy fixtures; Release construction cannot select a fixture.
- UI tests: About exposes `check-for-updates`; ready fixture is enabled and one click has no network dependency; busy fixture is disabled. Skip explicitly if SystemUIServer cannot expose the status item.
- Build tests: resolve the exact package pin and assert only the app links Sparkle; inspect generated Debug/Release Info.plists for exact feed URL, automatic-check disablement, and expected nonempty official public key. Search the built app and Pages artifact to prove no private-key bytes/path exist.
- Feed/E2E tests: with two disposable stable versions, assert no-update and upgrade flows, release-note display, confirmation before download, successful replacement/relaunch, invalid EdDSA, wrong code-signing identity, missing enclosure, offline failure, and preservation of the old runnable app. Exercise Apple Silicon and Intel when available.

### 9.7 Wrong vs Correct

#### Wrong

```swift
Button("检查更新") {
    SPUStandardUpdaterController(startingUpdater: true,
                                 updaterDelegate: nil,
                                 userDriverDelegate: nil)
        .checkForUpdates(nil)
}
```

The temporary controller has the wrong lifetime, the view owns infrastructure, and duplicate clicks are unguarded.

#### Correct

```swift
Button("检查更新") {
    appUpdater.checkForUpdates()
}
.disabled(!appUpdater.canCheckForUpdates)

func checkForUpdates() {
    guard canCheckForUpdates else { return }
    canCheckForUpdates = false
    checkAction() // Live composition forwards to the retained Sparkle controller.
}
```
