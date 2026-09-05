# Implementation Plan

## Ordered checklist

1. Extend the release build prerequisite checks to require `codesign` and keep Xcode's credential-free unsigned universal compilation unchanged.
2. After Bundle metadata/architecture validation, ad-hoc sign the complete app with identifier `com.youranreus.TokChan`.
3. Add strict pre-package verification and explicit metadata assertions for identifier, Info.plist coverage, and sealed resources.
4. Extract the staged ZIP into the owned temporary workspace and strictly verify the extracted app before checksum and final publication.
5. Extend shell fixtures with a deterministic `codesign` mock and tests for happy path, signing failure, pre-package verification failure, and post-extraction verification failure.
6. Update README, workflow step/release warning, build output, and release spec to describe complete ad-hoc signing accurately while retaining Gatekeeper/Developer ID/notarization caveats.
7. Run static, fixture, Xcode, and full release-build validation; inspect the produced ZIP's extracted Bundle signature.

## Validation commands

```bash
bash -n scripts/build-release.sh scripts/release.sh tests/test_release_scripts.sh
python3 tests/test_project_version.py
bash tests/test_release_scripts.sh
xcodebuild test -scheme TokChan -destination 'platform=macOS'
rm -rf dist-adhoc-check
scripts/build-release.sh --output dist-adhoc-check
unzip -t dist-adhoc-check/TokChan-v*-macos-universal.zip
```

Extract the final ZIP into a temporary directory and run:

```bash
codesign --verify --deep --strict --verbose=2 TokChan.app
codesign -dv --verbose=4 TokChan.app
```

Assert the designated identifier is `com.youranreus.TokChan`, Info.plist entries and sealed resources are present, and both architectures remain available. `spctl` may still reject or warn because ad-hoc signing is not Developer ID signing or notarization; that is expected and must remain documented.

## Manual verification

- Replace the installed app only after preserving/closing the currently running copy.
- Launch the newly packaged app from `/Applications` after any required manual Gatekeeper approval.
- Confirm Settings no longer reports a permanent `.notFound` solely due to an invalid Bundle signature.
- Toggle launch at login manually and verify the item appears in System Settings; do not automate this account-level change.

## Review gates before task start

- User approves the final planning summary.
- Both context manifests contain real release/signing specs and research.
- No Developer ID, notarization, secret management, or release publication work has entered scope.

## Risky files and rollback points

- `scripts/build-release.sh`: preserve cleanup ownership, final publication lock, and no-overwrite guarantees around every new failure path.
- `tests/test_release_scripts.sh`: mocks must validate command semantics without hiding failures in the real integration build.
- `.github/workflows/release.yml`: update both display copy and exact warning assertion together.
- Documentation: never imply ad-hoc signing provides Apple developer identity or Gatekeeper trust.
- No version increment, Tag, GitHub Release publication, or installed-app replacement occurs during implementation unless separately authorized.
