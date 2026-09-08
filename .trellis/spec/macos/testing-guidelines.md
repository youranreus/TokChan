# macOS Testing Guidelines

## Baseline

The Xcode project has `TokChanTests` and `TokChanUITests`; keep behavior checks deterministic and independent of live Tokscale services.

## Unit tests

- Test pure model logic and service behavior first.
- Test view models by injecting fake services.
- Cover loading, success, empty, and failure states for async flows.
- Test JSON decoding and persistence migration when those features exist.
- For dashboard refresh tests, inject the clock and sleep boundary. Cover the 300-second TTL edge, 30-second automatic-failure cooldown, trigger coalescing, popover visibility cancellation, and old account/generation responses without wall-clock sleeps.
- Treat an all/day/week/month refresh as one publication unit. Fail one remote request and assert no partial range becomes observable.
- Test status-item routing as pure behavior: left mouse-up toggles the dashboard, right mouse-up requests the native status menu, and unrelated events are ignored. For the `LSUIElement` popover opening path, assert exact `activate → show → makeKey` ordering; for the closing path, assert it only closes. Assert dynamic menu ordering both with and without freshness/diagnostics. Manual or UI validation must distinguish a temporary `statusItem.menu` presentation from a cursor-anchored context menu and must cover transient dismissal against both the desktop and another app.
- Test configurable status-item text as pure behavior: literal known-placeholder replacement, unknown-placeholder preservation, preference fallback/round-trip, complete same-account cache selection, and square/variable presentation. Because Combine `@Published` delivers its incoming value before storage changes, assert the coordinator path computes from the delivered preference rather than rereading stale view-model preferences.
- For manual status-menu transfer actions, assert push performs exactly one CLI submit and zero profile fetches, pull performs one complete batch and zero submits, any running explicit operation disables both descriptors, success is silent, and failure remains available through diagnostics.
- Test lifecycle races through popover visibility callbacks: closing clears a completed banner, does not cancel in-flight work, and suppresses a terminal success or failure from that closed generation after reopen.
- Test freshness with an injected `now`, locale, and timezone. Assert `yyyy-MM-dd` comparison uses Gregorian calendar components in the local timezone even when the supplied user calendar has another identifier.
- Test the Sparkle boundary without networking: an available manual check forwards once and disables synchronously, duplicates/unavailable checks forward zero, and publisher recovery re-enables a later check. The app composition root owns the controller; About only observes and invokes the adapter.
- Treat `--ui-testing` and `--updater-busy` as Debug-only dependency-selection inputs. UI tests assert the About button's ready/busy state using the offline adapter; Release-path tests prove these flags cannot substitute the live updater.

## UI tests

- Cover the real status-item path where the UI environment exposes it: left-click opens/closes the popover, right-click opens the menu without leaving the popover visible, and Settings opens or raises the SwiftUI-owned window. Skip explicitly when SystemUIServer does not expose the item rather than replacing these with live-network assumptions.
- Prefer stable accessibility identifiers only for controls that UI tests need.
- Do not rely on live network services in UI tests.

## SwiftUI previews

- Use previews as fast visual checks, not as a replacement for behavior tests.
- Preview data should be deterministic and local.

## Release/update pipeline tests

- Shell fixtures must enumerate the embedded Sparkle code graph and assert the inside-out partial order: Autoupdate, Updater.app, Downloader.xpc, and Installer.xpc all precede Sparkle.framework, which precedes TokChan.app. Assert preserved identifiers/requirements/entitlements and strict signature metadata on each component; `--deep` is verification-only, never a signing shortcut.
- Verify the local output transaction is exactly DMG, DMG SHA-256, and update ZIP. Extract the ZIP and revalidate its sole top-level app; do not accept `unzip -t` alone as proof of bundle identity, architecture, signature, or stapled ticket.
- Parse workflow YAML and test candidate generation separately from publication. Assert exact Actions permissions/Secrets/Variable/environment, exact draft asset set, immutable published-release handling, prior-feed preservation, EdDSA appcast fields, removal of private material, and Pages deployment only after the ZIP is publicly downloadable.
- Keep normal workflow tests deterministic and offline: every `uses:` entry must equal a reviewed allowlist tuple containing the action name, immutable lowercase 40-character SHA, and exact release version comment such as `v4.0.5`. Shape alone does not prove existence; a nonexistent but syntactically valid SHA makes Actions fail during job setup before checkout. Whenever a pin changes, run a separate explicit upstream check against the action's authoritative repository and exact tag (including annotated-tag peeling), then update the workflow and allowlist to the same reviewed commit. Do not perform this network verification on every test run.
- Mock first-feed 404 separately from transport/TLS/5xx/malformed-feed errors: only the verified bootstrap case may start empty. Publication or Pages failure must leave the prior feed discoverable and must never produce a partial public asset/feed state.
- Use local mocks and disposable feeds/repositories; unit and fixture suites must not use real Apple/EdDSA credentials, mutate a real GitHub Release, or deploy production Pages.

## Validation commands

Expected validation includes:

```bash
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS'
bash -n scripts/build-release.sh scripts/ci-build-release.sh scripts/release.sh tests/test_release_scripts.sh
python3 tests/test_project_version.py
python3 tests/test_ci_signing.py
bash tests/test_release_scripts.sh
```

Run `shellcheck` and `actionlint` when installed. Real signing/notarization and a two-version Sparkle update rehearsal remain manual production gates; mocked success is not equivalent.
