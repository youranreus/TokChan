# TokChan technical design

## Architecture

Create a dependency-free macOS 13 SwiftUI app in a conventional Xcode project. The app is an agent-style menu bar app (`LSUIElement`) whose primary scene is `MenuBarExtra` with `.window` style. The panel has a fixed compact width and a bounded tall height, with one vertical `ScrollView` containing overview, autosubmit status, grouped usage, and footer actions.

The implementation is split into four boundaries:

1. `DashboardView` renders the panel; `SettingsView` is hosted by a separate SwiftUI `Settings` scene.
2. `DashboardViewModel` owns explicit loading and operation states on `@MainActor` and coordinates dependencies.
3. `TokscaleAPIClient`, `TokscaleCLIClient`, and `PreferencesStore` own remote HTTP, child-process, and preference behavior.
4. Codable transport models are mapped into stable display models before reaching SwiftUI.

Use `ObservableObject` for macOS 13 compatibility. No third-party dependencies are required.

## UI composition

The menu panel is approximately 380 points wide and up to 680 points tall:

- header: avatar/username, online freshness, refresh button
- two-column compact metrics grid: tokens, cost, rank, active days
- autosubmit strip: enabled state, interval, last run/error, configure and run-now actions
- grouped usage list: client header with tokens/cost/percentage followed by model rows
- footer: settings and quit

All clients and models remain in the same scrollable first-level panel. Client and model groups are sorted by tokens descending, with stable identifier tie-breaking. Native system colors, typography, keyboard focus, accessibility labels, and dark mode are used.

Opening the panel first renders the last successful local snapshot, then triggers a read-only background load. It never submits implicitly. Existing content remains visible during refresh.

## Online data contract

`TokscaleAPIClient` calls:

```text
GET https://tokscale.ai/api/users/{percent-encoded-username}
```

MVP uses the default lifetime period. The decoder consumes:

- `user.username`, `displayName`, `avatarUrl`, `rank`
- `stats.totalTokens`, `totalCost`, `activeDays`
- `updatedAt`
- `contributions[].clients[]`
- each client entry's `client`, token buckets, `cost`, `messages`, and `models` dictionary

Client total tokens are the sum of input/output/cache-read/cache-write/reasoning buckets. Aggregate client and model totals across all contributions, then calculate the client percentage against displayed total tokens. Unknown JSON fields are ignored; optional external fields get safe defaults. HTTP 308 canonical redirects follow URLSession policy, 404 maps to an invalid or missing profile state, and other transport, status, and decode failures remain distinguishable for diagnostics.

## CLI contract

`TokscaleCLIClient` invokes `Process` with an absolute `npx` executable URL and a discrete argument array. It never passes user values through `/bin/sh -c` or an interpolated shell command.

The package selector is `tokscale@<version>`. Accept `latest` or a strict semantic version with an optional prerelease suffix. Reject whitespace, slashes, shell metacharacters, and arbitrary npm specifiers.

Supported operations:

```text
npx --yes tokscale@<version> whoami
npx --yes tokscale@<version> submit
npx --yes tokscale@<version> autosubmit status --json
npx --yes tokscale@<version> autosubmit enable --interval <duration> [filters]
npx --yes tokscale@<version> autosubmit disable
npx --yes tokscale@<version> autosubmit run --force
```

The app reads autosubmit exclusively from `status --json`. The form mirrors interval, clients, and one date-filter mode: all, today, yesterday, week, month, year, or since/until. Saving while enabled re-runs `enable` with the complete selected configuration; disabling invokes `disable`. The UI reloads status after every mutation.

Manual dashboard refresh uses `submit`, then fetches the profile. Run-now uses `autosubmit run --force`, then reloads status and profile. These are separate actions because manual refresh must remain available when autosubmit is disabled.

Capture stdout and stderr asynchronously, impose a reasonable timeout, terminate timed-out child processes, and return exit status plus sanitized output. Only one mutating CLI operation may run at a time.

## Executable and identity discovery

`NpxLocator` checks, in order:

1. a user-saved absolute executable path
2. the inherited process `PATH`
3. common Homebrew paths
4. installed NVM Node-version `bin/npx` paths under the user's home directory

If no executable is found, settings shows a path field and file picker. Every candidate must be an existing executable regular file.

Username is a normal preference. On first launch, attempt `whoami` and parse the labeled `Username:` line; if discovery fails, require manual entry before requesting the profile. The app never reads or persists Tokscale credential or token files.

## Persistence

Use a small `UserDefaults`-backed `PreferencesStore` for:

- username override
- Tokscale package version
- optional absolute `npx` path

Autosubmit state is not duplicated as configuration in `UserDefaults`; Tokscale remains its source of truth. UI draft values may exist only in memory until saved through the CLI.

Use a JSON snapshot under the app's caches directory for the most recently successful `DashboardData` and `AutosubmitStatus`, together with a cache timestamp. This is display acceleration only: cache corruption is ignored, mutations still go through Tokscale, and successful online/CLI reads replace the snapshot.

## Concurrency and state

`DashboardViewModel` is `@MainActor` and exposes explicit profile load, autosubmit load, and CLI operation states. Service methods are async. A new dashboard load cancels or supersedes stale read work, while mutating operations are serialized. UI updates happen only on the main actor.

Sequence contracts:

```text
panel opens -> render cache immediately -> [profile fetch || autosubmit status] -> replace cache and render
manual refresh -> submit -> profile fetch -> render
run now -> autosubmit run --force -> [profile fetch || autosubmit status] -> render
save autosubmit -> enable/disable -> autosubmit status -> render
```

## Security and distribution

The app is intentionally not App Sandbox enabled because Tokscale must scan user-level client data, write its configuration, install or manage a LaunchAgent, and execute or download the selected CLI package through `npx`. The intended MVP distribution is local or Developer ID rather than the Mac App Store.

No sensitive value is written by TokChan. Diagnostics must avoid dumping environment variables and token-bearing credential files.

## Testing strategy

- Fixture-based profile decoding and contribution aggregation tests.
- Fixture-based autosubmit status decoding tests, including disabled, stale executable, last error, and missing optional fields.
- Command-builder tests for every action, filter combination, version validation, and injection-shaped inputs.
- View-model tests with fake API, CLI, and preferences covering load, submit-before-fetch ordering, run-now reload ordering, stale results, and errors.
- Preferences round-trip tests using an isolated UserDefaults suite.
- One UI smoke test using launch arguments that inject deterministic fixture services; no real network, npx, submit, or launchd access.

## Rollback and compatibility

All external integrations sit behind service protocols, so a Tokscale contract change can be isolated to transport models and command construction. Autosubmit mutations always go through official CLI commands; a failed mutation leaves Tokscale's existing scheduler as managed by the CLI and surfaces the error without editing files directly.
