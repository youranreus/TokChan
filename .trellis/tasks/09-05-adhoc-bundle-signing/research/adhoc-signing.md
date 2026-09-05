# Complete ad-hoc Bundle Signing Research

## Root-cause evidence

The installed `/Applications/TokChan.app` (version 0.1.7) has correct metadata and runs from the expected location, but is not signed as an app bundle:

```text
Identifier=TokChan
Signature=adhoc,linker-signed
Info.plist=not bound
TeamIdentifier=not set
codesign --verify: code object is not signed at all
spctl --assess: rejected (no usable signature)
```

`scripts/build-release.sh` intentionally passes:

```text
CODE_SIGNING_ALLOWED=NO
CODE_SIGNING_REQUIRED=NO
CODE_SIGN_IDENTITY=''
```

This produces an unsigned bundle whose executable may retain linker-generated ad-hoc metadata. `SMAppService.mainApp` cannot reliably associate that executable-only signature with the bundle identifier and reports `.notFound`. The application directory is not the root cause.

## Proven minimum mechanism

A controlled test copied the installed app into a temporary directory and ran:

```bash
codesign --force --sign - --identifier com.youranreus.TokChan TokChan.app
codesign --verify --deep --strict --verbose=2 TokChan.app
codesign -dv --verbose=4 TokChan.app
```

The result was a complete ad-hoc Bundle signature:

```text
Identifier=com.youranreus.TokChan
Signature=adhoc
Info.plist entries=23
TeamIdentifier=not set
Sealed Resources version=2 rules=13 files=35
```

The signed app was packaged with the existing `ditto -c -k --keepParent`, extracted with `ditto -x -k`, and passed strict `codesign` verification after the ZIP round trip. This demonstrates that the current archive format preserves the Bundle signature.

## Recommended pipeline change

1. Keep Xcode code signing disabled during the universal build so GitHub CI remains credential-free and deterministic.
2. After validating version, build number, bundle ID, and architectures, run explicit whole-bundle ad-hoc signing:

   ```bash
   codesign --force --sign - --identifier "$bundle_identifier" "$app_path"
   ```

3. Immediately verify:

   ```bash
   codesign --verify --deep --strict --verbose=2 "$app_path"
   codesign -dv --verbose=4 "$app_path"
   ```

4. Require the reported identifier to equal `com.youranreus.TokChan` and ensure the bundle has a resource seal/Info.plist coverage.
5. Package the ZIP, extract it into a temporary verification directory, and run strict verification again before publishing final-named assets.
6. Preserve fail-closed cleanup: any sign/verify/extract failure leaves no final ZIP/checksum pair.

`--deep` is appropriate for verification. Do not use `--deep` to paper over nested signing order during signing; TokChan currently has no nested frameworks/helper executables, so signing the main bundle once is sufficient. If nested code is introduced later, sign nested code inside-out before signing the outer bundle.

## Test implications

The shell fixture creates a fake non-Mach-O executable, so it cannot use the host `codesign` implementation. Add a `codesign` mock that:

- records or validates the expected `--force --sign - --identifier com.youranreus.TokChan <app>` invocation;
- simulates signature metadata for subsequent verify/display calls;
- supports injected signing and verification failures;
- lets tests prove no final-named artifacts survive failures.

The real `scripts/build-release.sh` run remains the integration proof that host `codesign`, the actual universal app, and ZIP round-trip validation work together.

## Distribution semantics

A complete ad-hoc signature provides bundle integrity and a stable designated identifier on the machine where it is signed. It does not establish an Apple-verified developer identity, provide notarization, or guarantee Gatekeeper acceptance for downloaded users. Documentation and GitHub Release warnings must say “ad-hoc signed, not Developer ID signed, and not notarized” rather than calling the app bundle unsigned.

Developer ID signing, Hardened Runtime, notarization, stapling, and credential handling remain a future public-distribution hardening task.
