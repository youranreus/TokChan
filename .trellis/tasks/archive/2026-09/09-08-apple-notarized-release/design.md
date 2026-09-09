# Design

## Behavior boundary
Trust is established in scripts/build-release.sh and the CI credential/publication boundary. Replace the public ad-hoc path with explicit notarized mode while preserving credential-free local iteration. The user outcome is removal of manual Gatekeeper overrides, not removal of OS verification.

## Proposed flow
CI validates secrets, imports a Developer ID Application P12 into a temporary keychain, creates a notarytool keychain profile using Apple ID / app-specific password / Team ID, then requests notarized mode explicitly. Generate the temporary keychain password per run. Always remove imported credentials and restore keychain configuration on exit.

Build universal app with Xcode signing disabled as today. Explicitly codesign the complete app with Developer ID, hardened runtime and secure timestamp. Verify expected identifier, Team ID, certificate type and signature coverage. Do not introduce signing-time --deep or broad exception entitlements. Submit a temporary ZIP of the app using notarytool, require Accepted status, staple and validate app. Package existing DMG layout, sign DMG, submit and require Accepted, staple and validate DMG. Verify the mounted app and Gatekeeper acceptance before generating checksum and exposing final assets. Keep bounded waits and submission IDs/diagnostics for failures without leaking authentication material.

## File plan
- scripts/build-release.sh: explicit local/public mode, signature and notarization gates, immutable finalization order.
- scripts/lib/: small signing/notarization helper only if needed for lifecycle separation and testability.
- .github/workflows/release.yml: credential provisioning/cleanup, mandatory notarized build, truthful release notes and draft validation.
- README.md and docs/: installation expectations and maintainer setup guide.
- tests/: behavioral failure/success regressions for the new trust boundary and existing packaging contracts.
- .trellis/spec/macos/release-workflow.md: replace superseded ad-hoc-only public release contract.
- scripts/release.sh: only if needed to keep local preflight mode explicit and compatible.

## Proposed GitHub secrets
APPLE_CERTIFICATE_P12_BASE64: base64 of Developer ID Application certificate plus private key exported as P12.
APPLE_CERTIFICATE_PASSWORD: P12 export password.
APPLE_SIGNING_IDENTITY: complete Developer ID Application identity.
APPLE_TEAM_ID: developer team identifier.
APPLE_ID: Apple account login used for notarization.
APPLE_APP_SPECIFIC_PASSWORD: app-specific password, not account password.

Apple ID authentication is the initial supported route to minimize account setup; App Store Connect API-key support is deferred. No provisioning profile is planned for the current app capabilities; verify resolved entitlements before implementation.

## Risks and rollback
Real notarization requires user-supplied credentials and Apple service availability. Hardened runtime must preserve existing external-process behavior; smoke-test it. Existing release test mocks may encode old warning/signature assumptions. Roll back changes as a coherent set; never silently publish unsigned assets if notarization fails. Old immutable releases remain as historical artifacts.
