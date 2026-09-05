# Technical Design

## Architecture and boundaries

Keep the existing credential-free universal Xcode build, then add an explicit signing and verification stage inside `scripts/build-release.sh` before ZIP publication:

```text
xcodebuild unsigned universal app
  -> validate metadata and architectures
  -> codesign complete outer app bundle with identity "-"
  -> strict verify + inspect designated identifier
  -> ZIP
  -> extract into owned temporary verification directory
  -> strict verify extracted app
  -> checksum
  -> atomically publish final pair
```

No application source, Xcode signing identity, Apple certificate, or CI secret is required.

## Signing contract

After existing Bundle metadata and architecture checks, execute:

```bash
codesign --force --sign - --identifier "$bundle_identifier" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
```

Then inspect metadata with `codesign -dv --verbose=4` and assert:

- `Identifier=com.youranreus.TokChan`;
- the signature is ad-hoc rather than unsigned/linker-only;
- Info.plist entries and sealed resources are present.

TokChan currently has no nested executable code. Therefore sign the outer app once without signing-time `--deep`. If frameworks, XPC services, helpers, or plug-ins are introduced later, they must be signed inside-out before the outer bundle.

## ZIP round-trip verification

Package using the existing `ditto -c -k --keepParent`. Extract the staged ZIP into a new directory owned by the current run, assert the expected `TokChan.app` path exists, and run the same strict `codesign` verification there before checksum/final publication.

Add the extraction directory to the script's existing temporary workspace so the cleanup trap removes it on success or failure. Do not inspect or delete user-owned paths.

## Failure and publication behavior

Every signing, metadata inspection, extraction, and verification command runs under the existing fail-closed shell behavior. If any step fails:

- exit nonzero;
- retain the diagnostic build log according to the existing failure contract;
- clean owned staging/work paths;
- do not move a final-named ZIP or checksum into the output directory;
- never overwrite a pre-existing artifact.

The final publication lock and two-file move behavior remain unchanged.

## Test design

Extend `tests/test_release_scripts.sh` with a fixture-local `codesign` mock because its fake executable is not a Mach-O file. The mock should distinguish:

- signing (`--force --sign - --identifier ...`);
- strict verification (`--verify --deep --strict ...`);
- metadata display (`-dv --verbose=4`).

It should record the signed Bundle path, emit representative metadata, and support environment-controlled failures. Tests assert:

1. the normal fixture calls complete Bundle signing with the expected identifier;
2. signing failure leaves no final artifact pair;
3. original-app verification failure leaves no final pair;
4. extracted-app verification failure leaves no final pair;
5. the happy-path ZIP/checksum behavior remains unchanged.

The real `scripts/build-release.sh` integration run verifies actual `codesign` behavior on the universal app.

## Documentation and workflow copy

Update:

- `README.md` release warning;
- `.github/workflows/release.yml` step name and GitHub Release warning/body assertion;
- `scripts/build-release.sh` progress and final warning text;
- `.trellis/spec/macos/release-workflow.md` signing, validation, and test contracts.

All wording must consistently say the app is **ad-hoc signed**, **not Developer ID signed**, and **not Apple-notarized**. Gatekeeper warnings remain expected for downloads.

## Compatibility and rollback

`codesign` and `ditto` are built into supported macOS/Xcode CI environments. The output asset names and update/version contract do not change.

Rollback restores the previous unsigned package behavior, but would reintroduce the confirmed `SMAppService.mainApp` incompatibility. No user data or source migration is involved.
