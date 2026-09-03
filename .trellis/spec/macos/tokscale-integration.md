# Tokscale Integration Contract

## Scenario: Public profile and official autosubmit orchestration

### 1. Scope / Trigger

Use this contract whenever code reads Tokscale profile data, executes Tokscale through `npx`, or changes the autosubmit UI. TokChan is an adapter around Tokscale's public API and official CLI; it must not implement a second scheduler or edit Tokscale configuration files directly.

### 2. Signatures

```text
GET https://tokscale.ai/api/users/{username}

npx --yes tokscale@<version> whoami
npx --yes tokscale@<version> submit
npx --yes tokscale@<version> autosubmit status --json
npx --yes tokscale@<version> autosubmit enable --interval <Nm> [filters]
npx --yes tokscale@<version> autosubmit disable
npx --yes tokscale@<version> autosubmit run --force
```

Swift boundaries:

```swift
protocol TokscaleAPIService {
    func fetchProfile(username: String) async throws -> DashboardData
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
- A saved `npx` override must be an absolute executable file. Discovery checks inherited `PATH`, Homebrew, and `~/.nvm/versions/node/*/bin/npx` in numeric version order.
- Before launching `npx`, prepend its containing directory to the child `PATH`. NVM's `npx` uses `#!/usr/bin/env node`; finding the script alone is insufficient in a Finder-launched GUI environment.
- Profile mapping reads `user`, `stats`, `updatedAt`, and `contributions[].clients[]`; unknown JSON keys are ignored and optional token buckets default to zero.
- `AutosubmitStatus` reads enablement, interval, scheduler, clients, date flags/range, managed executable/version/staleness, last run milliseconds, and last error.
- Only username, Tokscale version, and optional `npx` path belong in `UserDefaults`. A separate disposable caches-directory snapshot may contain mapped display data and the last observed autosubmit status; see `data-persistence.md`.

### 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Blank username | `TokscaleAPIError.invalidUsername`; prompt for Settings |
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

### 5. Good / Base / Bad Cases

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

- Decode current and sparse public profile fixtures; assert grouped client/model totals, percentages, and token-descending order.
- Decode current and sparse autosubmit JSON; assert defaults and date summary.
- Assert every command's exact argument suffix and rejection of invalid version, client, interval, and dates.
- Execute a fixture `npx` with an `/usr/bin/env` shebang; assert sibling runtime resolution through the prepended child `PATH`.
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
