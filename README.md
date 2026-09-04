# TokChan

TokChan is a compact native macOS menu-bar companion for [Tokscale](https://tokscale.ai). It shows Tokscale all-time, daily, trailing-week, and trailing-month totals plus client/model detail and manages Tokscale's built-in autosubmit through its official CLI.

## Requirements

- macOS 13 or later
- Xcode 15 or later
- Node.js with an executable `npx`
- An existing Tokscale login for submission and autosubmit operations

## Run

Open `TokChan.xcodeproj` and run the `TokChan` scheme, or build from the repository root:

```bash
xcodebuild -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' build
```

TokChan is an agent-style app, so it appears in the menu bar and does not create a Dock icon. The first panel load discovers the current Tokscale username with `whoami` when no override is saved.

## Integration behavior

- The panel keeps statistics fixed while the client list scrolls. Each client starts with its top five models and can expand; client logos ship in the app.
- Period tabs use Tokscale’s own range boundaries and five-category Tokens breakdown. Daily usage comes from the server’s end-date contribution bucket; daily rank is unavailable.
- Opening the panel only reads the public profile and `autosubmit status --json`.
- All scope snapshots and the selected tab are cached in a local JSON file. Reopening or switching to a cached scope does not fetch again; submit/refresh updates the selected scope.
- Refresh runs `submit` first, then reloads the public profile.
- Autosubmit status and “Run now” appear in Settings. Settings apply autosubmit changes through `enable` or `disable`; “Run now” uses `autosubmit run --force`.
- Every command uses `npx --yes tokscale@<configured-version>` with an argument array, without shell interpolation.
- TokChan stores only username, package version, and an optional absolute `npx` path. Tokscale remains the source of truth for credentials and autosubmit state.

The app intentionally does not enable App Sandbox because Tokscale needs local client-data access and manages its own macOS LaunchAgent.
