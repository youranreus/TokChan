# Technical Design

## Architecture and boundaries

Keep the existing credential-free universal build and complete ad-hoc App signing. Replace only the ZIP packaging boundary with a native DMG pipeline:

```text
xcodebuild unsigned universal app
  -> validate metadata and architectures
  -> ad-hoc sign complete app bundle
  -> strict verify signed app
  -> stage TokChan.app + /Applications symlink
  -> build writable image and persist a minimal Finder icon layout
  -> convert to compressed read-only DMG
  -> verify and mount DMG at an owned temporary mount point
  -> validate root contents, symlink, architectures, metadata, and signature
  -> detach
  -> checksum
  -> atomically publish DMG/checksum pair
```

No application source, signing identity, Apple certificate, CI secret, third-party package manager, or network-fetched packaging tool is required.

## DMG contract

The final assets are:

```text
TokChan-vX.Y.Z-macos-universal.dmg
TokChan-vX.Y.Z-macos-universal.dmg.sha256
```

The volume name is `TokChan`. Its root contains these user-visible entries:

- `TokChan.app`, copied from the verified Release build;
- `Applications`, a symbolic link whose target is exactly `/Applications`.

A generated `.DS_Store` may also exist as hidden Finder metadata. The Finder window uses icon view, a fixed window size, hidden toolbar/status bar, and two side-by-side icons. It has no custom background image. The App remains on the left and Applications on the right, matching the drag-to-install direction.

Use only macOS system tools (`hdiutil`, `osascript`, `codesign`, `lipo`, `shasum`) plus the already-required Python interpreter. Build a temporary writable image for Finder metadata, detach it, then convert it to a compressed read-only UDZO image. Do not commit an opaque `.DS_Store` template and do not add Homebrew/npm/pip packaging dependencies.

## Mounting and cleanup contract

Every staging directory, image, mount point, and Finder metadata file belongs to the current temporary workspace. `hdiutil attach -plist` output is parsed structurally to capture the attached device and mount point instead of relying on localized text output.

The cleanup trap tracks attached devices separately from published files. On success or failure it must:

1. detach any image attached by the current run;
2. remove only current-run temporary resources;
3. remove current-run final assets if publication failed partway through;
4. preserve all pre-existing files, symlinks, foreign mounts, and foreign publication locks.

Finder layout automation is fail-closed: an AppleScript failure, missing `.DS_Store`, detach failure, image conversion failure, or verification mount failure prevents final publication. Layout operations must target the owned mounted volume and must not mutate `/Applications` or any installed App.

## Verification contract

Before publication:

1. run `hdiutil verify` on the staged compressed image;
2. attach it read-only, with auto-open disabled, at an owned temporary mount point;
3. assert `TokChan.app` exists and `Applications` is a symlink to `/Applications`;
4. reject unexpected user-visible root entries;
5. read the App version, build, and bundle identifier from the mounted image and compare them with source values;
6. verify the mounted executable still contains arm64 and x86_64;
7. run the existing strict `codesign` and metadata checks against the mounted App;
8. detach successfully before checksum creation and publication.

The checksum records the DMG basename so `shasum -a 256 -c` works from the download directory.

## GitHub Release contract

`.github/workflows/release.yml` changes from the exact ZIP/checksum pair to the exact DMG/checksum pair. Draft-resume, published-release immutability, warning-text checks, and publish-after-exact-assets behavior remain unchanged.

The Release body and local output continue to state that the App is ad-hoc signed, not Developer ID signed, and not Apple-notarized. A DMG improves installation UX but does not improve Gatekeeper trust.

## Test design

Extend `tests/test_release_scripts.sh` rather than introducing a separate framework:

- update fixture names and release-script fixture outputs from ZIP to DMG;
- add deterministic mocks for `hdiutil` and Finder layout automation;
- assert staging contains the App and exact `/Applications` symlink;
- assert image verification and mounted-App signature verification occur;
- cover layout, image creation/conversion, attach, content, symlink, post-package signature, detach, and checksum failures;
- retain no-overwrite, dangling-symlink preservation, publication-lock, partial-move cleanup, workflow draft retry, and warning-text coverage;
- syntax-check workflow shell blocks and run the real local build as the integration proof.

Manual verification opens the real DMG in Finder and confirms the fixed two-icon layout and drag-to-Applications interaction.

## Compatibility, risk, and rollback

- The target App already requires macOS 13; an HFS+/UDZO DMG remains broadly compatible with supported systems.
- Finder scripting may be sensitive to CI session behavior. The implementation must use bounded waits/retries and fail rather than publishing an unconfigured image.
- DMG creation adds attach/detach state, so device tracking and cleanup are the highest-risk implementation area.
- Rollback restores the ZIP packaging section, old asset names, tests, workflow contract, README, and release spec together. No user data migration is involved.
