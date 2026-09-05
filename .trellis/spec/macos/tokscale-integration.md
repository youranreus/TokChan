# Tokscale Integration Contract

## Scenario: Public profile and official autosubmit orchestration

### 1. Scope / Trigger

Use this contract whenever code reads Tokscale profile data, executes Tokscale through `npx`, changes the autosubmit UI, or manages custom pricing. TokChan is an adapter around Tokscale's public API and official CLI; it must not implement a second scheduler. Direct Tokscale file writes are forbidden except for the explicitly scoped `custom-pricing.json` contract below.

### 2. Signatures

```text
GET https://tokscale.ai/api/users/{username}?period=all|week|month

npx --yes tokscale@<version> whoami
npx --yes tokscale@<version> submit
npx --yes tokscale@<version> autosubmit status --json
npx --yes tokscale@<version> autosubmit enable --interval <Nm> [filters]
npx --yes tokscale@<version> autosubmit disable
npx --yes tokscale@<version> autosubmit run --force
npx --yes tokscale@<version> pricing list-overrides --json
npx --yes tokscale@<version> submit --dry-run
```

Swift boundaries:

```swift
protocol TokscaleAPIService {
    func fetchProfile(username: String, period: ProfilePeriod) async throws -> DashboardData
}

protocol TokscaleCLIService {
    func whoAmI(context: TokscaleCommandContext) async throws -> String
    func submit(context: TokscaleCommandContext) async throws
    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus
    func configureAutosubmit(_ configuration: AutosubmitConfiguration,
                             context: TokscaleCommandContext) async throws
    func disableAutosubmit(context: TokscaleCommandContext) async throws
    func runAutosubmitNow(context: TokscaleCommandContext) async throws
}
```

### 3. Contracts

- Package version is `latest` or strict `major.minor.patch` with an optional prerelease suffix.
- Commands use `Process.executableURL` plus a discrete `[String]` argument array; never use `/bin/sh -c`.
- A saved `npx` override must be an absolute executable file. Discovery preserves the deterministic precedence override → inherited `PATH` → fixed Homebrew/system paths → stable manager selections → installed-version fallbacks. It supports fnm, Volta, asdf, mise, nodenv, n, and nvm from their fixed macOS defaults and inherited absolute root overrides. Selected/default candidates precede strict stable `major.minor.patch` fallbacks; candidate paths are normalized and deduplicated, and the final target must exist, not be a directory, and be executable. Discovery only reads bounded known filesystem locations: it never starts a shell or manager, and it excludes fnm multishell paths, generic asdf/mise/nodenv shims, n caches, malformed versions, and unsafe config/alias tokens. Volta's documented `$VOLTA_HOME/bin/npx` shim is the sole manager-shim exception.
- Settings present an empty override as automatic discovery and display the resolved executable path. Keep manual selection collapsed when automatic discovery succeeds; expand recovery controls for missing discovery or an invalid saved override. Clearing the override restores automatic mode without changing the persisted schema.
- Before launching `npx`, prepend its containing directory to the child `PATH`. NVM's `npx` uses `#!/usr/bin/env node`; finding the script alone is insufficient in a Finder-launched GUI environment.
- Profile mapping reads `period`, `dateRange`, `user`, `stats`, `updatedAt`, and `contributions[].clients[]`. The request and response period must match. The API supports only `all`, `week` (trailing 7 days), and `month` (trailing 30 days); it does not accept `day` as a remote period. The visible day tab fetches week and projects the contribution whose date equals dateRange.end. Use its totals/tokenBreakdown/clients verbatim; return nil rank because there is no daily rank. No matching day means zero usage. Use returned date boundaries, not local calendar calculations.
- Metric cards and rank use the selected response directly. In `all`, upstream activeDays follows its chart window; never silently recompute it as lifetime days.
- Overall breakdown comes from stats inputTokens/outputTokens/cacheReadTokens/cacheWriteTokens/reasoningTokens. Missing stats categories produce an unavailable breakdown, not fabricated zeros. Sparse client buckets retain zero defaults for existing aggregation compatibility.
- TokenCategory fixes the five legend/segment order. Bar fractions use the sum of finite nonnegative categories, normalized before summation to avoid overflow. Do not replace API totalTokens with that sum.
- Profile reloads return an explicit updated/failed/superseded outcome to mutation callers; do not infer their success from a shared error cleared by another request. Re-resolve CLI context after suspended identity discovery, since Settings may have changed npx/version.
- Switching scope is read-only; it neither submits nor reads/modifies autosubmit. Guard profile requests by generation, account and scope so late responses cannot replace the selected view. Keep identity visible while missing scoped data loads.
- Autosubmit status details and run-now live in Settings, with progress/success/failure feedback. Run-now uses persisted CLI settings, not unsaved form drafts.
- `AutosubmitStatus` reads enablement, interval, scheduler, clients, date flags/range, managed executable/version/staleness, last run milliseconds, and last error.
- Only username, Tokscale version, and optional `npx` path belong in `UserDefaults`. A separate disposable caches-directory snapshot may contain mapped display data and the last observed autosubmit status; see `data-persistence.md`.
- Custom pricing management first resolves the effective path through `pricing list-overrides --json`, then reads and mutates only that `custom-pricing.json`. Credentials, `settings.json`, LaunchAgents, and scheduler state remain out of bounds.
- Treat the raw JSON document as the lossless source of truth; the CLI list response is only a path/effective-entry projection. Preserve unedited metadata, unknown keys, tier fields, compatible aliases, and decimal number semantics without routing untouched JSON numbers through binary floating-point. A missing file may become a minimal `models` document, but malformed documents must never be rebuilt as empty.
- Custom-pricing writes compare the previously loaded bytes immediately before an atomic replacement. External changes stop the write and require reload. Editing a base rate removes all aliases for that selected rate and writes the canonical per-million key; untouched rates retain their original representation.
- Price values are USD per million Tokens in the UI. Missing and explicit zero are distinct. Reject non-finite/negative values, case-insensitive duplicate model IDs, and entries without either input or output pricing.
- Missing-price checks use persisted npx/version settings and exactly `submit --dry-run` with the CLI default range. They never invoke plain `submit`, `autosubmit run`, or save unrelated Settings drafts. Parse complete stdout/stderr after removing ANSI escapes and keep missing-price rows even when an all-unpriced summary says no data. Tokscale 4.15.x prints `unpriced provider/model message(s)` (not `unpriced message(s): provider/model`); current output may cap detail rows and list the remaining IDs separately.
- Fix-up matching first uses Tokscale's case-insensitive exact key, then its documented Synthetic normalization (`hf:org/model` or `accounts/<provider>/models/<model>`). Exact matches win; ambiguous normalized matches must never be silently rewritten or duplicated.
- A diagnostic pass requires a recognized dry-run completion marker, no unparsed pricing-failure signal, and no degraded scanner/pricing-source warning. Unknown formats, no-data results, partial-source results, failures, and verified no-missing results are separate states. Any file/context change makes an existing report stale until another dry-run.

### 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Blank username | `TokscaleAPIError.invalidUsername`; prompt for Settings |
| Response period differs from request | Reject with mismatchedPeriod; never relabel the response |
| Profile HTTP 404 | `profileNotFound` |
| Other non-2xx response | Preserve HTTP status in `server(statusCode:)` |
| Missing/non-executable `npx` | `TokscaleCLIError.missingNpx` |
| Arbitrary npm specifier or shell-shaped version | `invalidVersion` before process launch |
| Interval outside 1...525600 minutes | `invalidInterval` |
| Unknown/shell-shaped client identifier | `invalidClient` |
| Impossible or reversed date range | `invalidDateFilter` |
| CLI non-zero exit | Surface exit code and at most 4,000 characters of stderr/stdout |
| CLI timeout | Terminate the child and surface `ProcessRunnerError.timedOut` |
| Invalid status JSON | `invalidStatusJSON`, without changing autosubmit |
| Invalid pricing-list JSON/path | Fail loading; do not guess the default directory |
| Missing custom-pricing file | Show an addable empty state; create only on explicit save |
| Malformed custom-pricing JSON/models | Block writes and preserve the original bytes |
| File changed since load | Abort with a reload-required conflict; never overwrite external edits |
| Unknown/degraded dry-run output | Preserve details and show indeterminate/partial, never a clean pass |

### 5. Good / Base / Bad Cases

- Good: requesting `period=week` displays the returned range, stats and contribution groups together.
- Bad: requesting `day`, calculating local week boundaries, or showing lifetime cached totals beneath a selected week tab.
- Good: `npx --yes tokscale@4.15.0 autosubmit enable --interval 120m --client codex --week` is built as individual arguments, then status is re-read.
- Base: opening the panel concurrently fetches profile data and reads autosubmit status; it performs no submission.
- Bad: interpolating `"npx tokscale@\(version) ..."` into a shell, accepting `latest;rm`, reading token files, or writing LaunchAgent/settings JSON from TokChan.


### Convention: Settings Scene Window Invocation

**What**: When the app declares a SwiftUI `Settings` scene, the menu-bar dashboard's settings control uses `SettingsLink` on macOS 14 and later. The macOS 13 compatibility branch may send `showSettingsWindow:` because `SettingsLink` is unavailable there.

**Why**: Sending the legacy selector from the primary macOS 14+ path is not a reliable bridge to a SwiftUI `Settings` scene, so the button can appear to do nothing.

**Example**:
```swift
if #available(macOS 14.0, *) {
    SettingsLink {
        Label("设置", systemImage: "gearshape")
    }
} else {
    Button { openSettingsWindowOnLegacySystem() } label: {
        Label("设置", systemImage: "gearshape")
    }
}
```

**Test**: Keep a stable `settings-button` accessibility identifier and cover the supported-system view path with a regression test.
### 6. Tests Required

- Verify exact URL period/username encoding and reject mismatched response scope.
- Resolve month before an earlier week request; assert month remains visible. Test failed scope loads never reuse a different scope cache.
- Assert five-category fractions, empty values, malformed values and bundled icon resolution.
- Decode current and sparse public profile fixtures; assert grouped client/model totals, percentages, and token-descending order.
- Decode current and sparse autosubmit JSON; assert defaults and date summary.
- Assert every command's exact argument suffix and rejection of invalid version, client, interval, and dates.
- Execute a fixture `npx` with an `/usr/bin/env` shebang; assert sibling runtime resolution through the prepended child `PATH`.
- Locator unit tests must inject or clear fixed system candidates; an empty `PATH` alone does not isolate Homebrew or `/usr/local` tools installed on CI runners. Cover explicit override/PATH/fixed precedence; every supported manager's default and absolute environment-root layout; selected/default preference; strict stable semantic sorting; deterministic cross-manager order; excluded shims, multishells and caches; broken aliases; unsafe roots/config tokens; and directory or non-executable impostors.
- Settings tests must cover automatic/custom/fallback/unavailable presentation, including whether override controls start collapsed or expanded; locator tests separately prove executable discovery and precedence.
- Custom-pricing file tests use temporary directories and cover missing/malformed files, add/edit/delete, zero versus nil, aliases, unknown/tier field preservation, duplicate IDs, and external-change conflicts.
- Fixture tests cover legacy excluded-unpriced output, current zero-cost unpriced output, all-unpriced zero summaries, no data, degraded sources, ANSI output, and unknown formats. A fake runner must assert the exact `pricing list-overrides --json` and `submit --dry-run` suffixes and prove no real submit command runs.
- With fake services, assert panel load performs only `fetch` and `status`; manual refresh orders `submit` before `fetch`; run-now orders `run` before profile/status reload.
- UI smoke tests must use `--ui-testing` fixture dependencies and never access the network, `npx`, or `launchd`.

### 7. Wrong vs Correct

#### Wrong

```swift
process.executableURL = URL(fileURLWithPath: "/bin/sh")
process.arguments = ["-c", "npx tokscale@\(version) autosubmit enable ..."]
```

This enables shell injection and still fails for NVM when a GUI process lacks the interactive shell environment.

#### Correct

```swift
process.executableURL = locatedNpxURL
process.arguments = ["--yes", "tokscale@\(validatedVersion)", "autosubmit", "status", "--json"]
environment["PATH"] = "\(locatedNpxURL.deletingLastPathComponent().path):\(inheritedPath)"
```
