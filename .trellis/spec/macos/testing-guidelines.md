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
- Test status-item routing as pure behavior: left mouse-up toggles the dashboard, right mouse-up requests the native status menu, and unrelated events are ignored. Assert dynamic menu ordering both with and without freshness/diagnostics. Manual or UI validation must distinguish a temporary `statusItem.menu` presentation from a cursor-anchored context menu.
- Test lifecycle races through popover visibility callbacks: closing clears a completed banner, does not cancel in-flight work, and suppresses a terminal success or failure from that closed generation after reopen.
- Test freshness with an injected `now`, locale, and timezone. Assert `yyyy-MM-dd` comparison uses Gregorian calendar components in the local timezone even when the supplied user calendar has another identifier.

## UI tests

- Cover the real status-item path where the UI environment exposes it: left-click opens/closes the popover, right-click opens the menu without leaving the popover visible, and Settings opens or raises the SwiftUI-owned window. Skip explicitly when SystemUIServer does not expose the item rather than replacing these with live-network assumptions.
- Prefer stable accessibility identifiers only for controls that UI tests need.
- Do not rely on live network services in UI tests.

## SwiftUI previews

- Use previews as fast visual checks, not as a replacement for behavior tests.
- Preview data should be deterministic and local.

## Validation commands

Once the project exists, expected validation should include an Xcode build and test command such as:

```bash
xcodebuild test -scheme TokChan -destination 'platform=macOS'
```

Update the simulator name and scheme to match the generated project.
