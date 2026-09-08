# Validation — 2026-09-08

## Completed
- Implemented explicit --notarize public build; default local ad-hoc retained.
- CI imports six approved secrets into a temporary keychain, cleans up and restores keychain search list/umask. No raw credentials enter child build environment.
- App and DMG notarization/stapling precede checksum and publication. Formal failure paths never fall back.
- README, setup guide and release spec synchronized.
- Independent trellis-check review completed. Fixed inherited credential umask and ephemeral-only CI diagnostics.
- `bash tests/test_release_scripts.sh`: 67 checks passed, including Apple rejection diagnostics; fake-ticket mutations prove checksum order.
- `python3 tests/test_ci_signing.py`: 8 tests passed.
- `python3 tests/test_project_version.py`: 7 tests passed.
- Bash syntax, workflow YAML parse and every workflow run block syntax passed; git diff --check passed.
- Final real `scripts/build-release.sh --output /tmp/tokchan-signing-local-validation-0908` passed outside sandbox: 175 unit tests, universal app, strict ad-hoc signature checks, Finder DMG packaging, read-only mounted app/content validation and final checksum.
- Build log: `/tmp/tokchan-signing-local-validation-0908.log`. Local artifact is deliberately ad-hoc and not for public upload.

## Environment notes
Sandboxed Xcode failed to resolve build settings/services. Approved unsandboxed build passed. An intermediate real run was interrupted by concurrent edits to its executing shell script; final validation ran against frozen scripts and passed. shellcheck and actionlint are not installed.

## Remaining acceptance
User must configure six GitHub Secrets following docs/macos-release.md. Real Developer ID signing, Apple service acceptance, stapled ticket Gatekeeper behavior, clean-Mac browser-download launch and offline launch remain unverified until credentials and a formal build are available. No release/tag/version changes, pushes or published asset mutations were performed. User approved the local implementation commit. Task remains in_progress pending credential-dependent external acceptance; no push or publication is authorized by this commit approval.
