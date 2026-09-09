# Apple-notarized macOS releases

## Goal
Users downloading new official GitHub releases can install and launch TokChan under default Gatekeeper settings without unidentified-developer or unnotarized-software overrides.

## Background
The user has obtained an Apple developer account and authorized creating this Trellis task. Current scripts/build-release.sh signs ad-hoc; .github/workflows/release.yml requires unnotarized warning text. Distribution is a universal arm64/x86_64 DMG plus SHA-256. Existing scripts/release.sh prepares versions and tags with a local build.

## Requirements
- R1: Official CI releases must use Developer ID Application signing and Apple notarization; missing credentials or failed verification must prevent publication, without ad-hoc fallback.
- R2: Preserve version/tag checks, universal architecture, drag-to-Applications layout, checksum pair, and published-release immutability.
- R3: Staple tickets for offline ticket availability; calculate checksum only after all artifact mutations.
- R4: Document exact GitHub credential setup and local build behavior. Never commit credentials or request private key contents in chat.
- R5: Update installation and release text to match verified official artifacts.

## Acceptance
- Correct Developer ID, Team ID, hardened runtime, secure timestamp, strict bundle signature and accepted notarization are verified before publication.
- Both app and final DMG have valid stapled tickets; mounted app passes Gatekeeper assessment.
- Missing/invalid credentials, rejected/pending notarization, failed stapling or signature checks produce no published release.
- Existing release and packaging regressions pass; local credential-free iteration remains possible and clearly labeled.
- A browser-downloaded new official artifact is manually tested on a clean Mac under default Gatekeeper settings, including an offline launch check after install. This requires configured Apple credentials and a real release artifact.

## Scope limits
No App Store submission, updater, app UI changes, version bump, tag push or release publication in this task. macOS may still show its normal first-launch download confirmation or verification progress; system checks and organizational policies cannot be disabled by packaging. Previously published assets stay unchanged.
