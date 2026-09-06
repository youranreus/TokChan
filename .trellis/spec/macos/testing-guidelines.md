# macOS Testing Guidelines

## Baseline

No test target exists yet. When the Xcode project is created, include unit tests and UI tests unless there is a deliberate reason not to.

## Unit tests

- Test pure model logic and service behavior first.
- Test view models by injecting fake services.
- Cover loading, success, empty, and failure states for async flows.
- Test JSON decoding and persistence migration when those features exist.
- For dashboard refresh tests, inject the clock and sleep boundary. Cover the 300-second TTL edge, 30-second automatic-failure cooldown, trigger coalescing, panel visibility cancellation, and old account/generation responses without wall-clock sleeps.
- Treat an all/day/week/month refresh as one publication unit. Fail one remote request and assert no partial range becomes observable.

## UI tests

- Add UI tests for the main happy path once the first user flow exists.
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
