# Apple distribution research — 2026-09-08

- https://developer.apple.com/developer-id/ : outside-store distribution uses Developer ID; custom workflows use notarytool and stapler.
- https://developer.apple.com/documentation/security/customizing-the-notarization-workflow : notarytool submission/status/log and stapler workflow; Apple ID with app-specific password is a supported authentication route.
- https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications : store exported P12 base64/password in GitHub secrets and import into a temporary macOS keychain. Clean up after use.
- https://support.apple.com/en-us/102445 : Gatekeeper checks identified-developer signatures and notarization; even identified apps can receive the normal first-launch Internet-download confirmation. Organizational/App-Store-only restrictions are distinct.

Repository evidence: scripts/build-release.sh currently requires Signature=adhoc and TeamIdentifier=not set; CI release body validation mandates unnotarized warnings. Both checks must evolve together. scripts/release.sh invokes the local build before creating a tag, so local iteration must not accidentally require CI credentials.
