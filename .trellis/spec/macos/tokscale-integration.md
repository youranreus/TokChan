# Tokscale Integration Contract

## Scenario: Public profile and official autosubmit orchestration

### 1. Scope / Trigger

Use this contract whenever code reads Tokscale profile data, executes Tokscale through `npx`, changes the autosubmit UI, or manages custom pricing. TokChan is an adapter around Tokscale's public API and official CLI; it must not implement a second scheduler. Direct Tokscale file writes are forbidden except for the explicitly scoped `custom-pricing.json` contract below.

### 2. Signatures

```text
GET https://tokscale.ai/api/users/{username}?period=all|week|month

npx --yes tokscale@<version> whoami
npx --yes tokscale@<version> cursor login
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
    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch
}

protocol TokscaleCLIService {
    func whoAmI(context: TokscaleCommandContext) async throws -> String
    func loginCursor(context: TokscaleCommandContext) async throws
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
- Cursor login is one fixed explicit mutation: resolve the persisted npx/version context and execute exactly `npx --yes tokscale@<version> cursor login`. It participates in the shared explicit-operation exclusion. Success publishes dedicated feedback and performs zero `cursor sync`, submit, profile fetch, autosubmit-status read, configure, disable, or run-now follow-ups. Every failure reuses normal context/process error mapping and offers the safe presentation-only fallback `npx tokscale@<validated-version> cursor login`; invalid versions use `latest` in fallback copy rather than reproducing shell-shaped text. TokChan never reads, prompts for, stores, or forwards Cursor cookies/tokens.
- Temporary launchd compatibility exception: only when `autosubmit enable` returns a nonzero result whose combined raw stdout/stderr contains all four confirmed Tokscale defect signatures — `launchd bootout failed`, `launchctl bootout --wait`, `exit status: 64`, and `Unrecognized target specifier` — TokChan may run `/bin/launchctl` once with the discrete arguments `bootout` and `gui/<effective-uid>/ai.tokscale.autosubmit`. After launchd cleanup succeeds, TokChan must run the same configured Tokscale CLI's `autosubmit disable` exactly once with `TOKSCALE_AUTOSUBMIT_SKIP_SCHEDULER=1` scoped only to that child process, require it to succeed, and then retry the identical enable command exactly once with the normal environment. The executable path and service label are fixed constants; do not derive either from CLI output, accept a missing service, invoke a shell, recurse, leak the environment override to enable, or apply this recovery to user-requested disable/run/submit/other commands. Launchd cleanup and Tokscale state-cleanup failures identify their respective failed step with sanitized exit details, retry failure retains normal CLI error behavior, and status verification remains the view model's existing single read after successful configuration. Remove this classifier, direct launchctl call, recovery-only environment override, and focused tests together once the minimum supported Tokscale version includes the upstream fix.
- A saved `npx` override must be an absolute executable file. Discovery preserves the deterministic precedence override → inherited `PATH` → fixed Homebrew/system paths → stable manager selections → installed-version fallbacks. It supports fnm, Volta, asdf, mise, nodenv, n, and nvm from their fixed macOS defaults and inherited absolute root overrides. Selected/default candidates precede strict stable `major.minor.patch` fallbacks; candidate paths are normalized and deduplicated, and the final target must exist, not be a directory, and be executable. Discovery only reads bounded known filesystem locations: it never starts a shell or manager, and it excludes fnm multishell paths, generic asdf/mise/nodenv shims, n caches, malformed versions, and unsafe config/alias tokens. Volta's documented `$VOLTA_HOME/bin/npx` shim is the sole manager-shim exception.
- Settings present an empty override as automatic discovery and display the resolved executable path. Keep manual selection collapsed when automatic discovery succeeds; expand recovery controls for missing discovery or an invalid saved override. Clearing the override restores automatic mode without changing the persisted schema.
- Before launching `npx`, prepend its containing directory to the child `PATH`. NVM's `npx` uses `#!/usr/bin/env node`; finding the script alone is insufficient in a Finder-launched GUI environment.
- Profile mapping reads `period`, `dateRange`, `user`, `stats`, `updatedAt`, and `contributions[].clients[]`. The request and response period must match. The API supports only `all`, `week` (trailing 7 days), and `month` (trailing 30 days); it does not accept `day` as a remote period. The visible day tab fetches week and projects the contribution whose date equals dateRange.end. Use its totals/tokenBreakdown/clients verbatim; return nil rank because there is no daily rank. No matching day means zero usage. Use returned date boundaries, not local calendar calculations.
- Dashboard refresh issues all/week/month concurrently with a finite request timeout and HTTP cache revalidation. Decode the week response once and derive both day and week. Return only an exact four-scope, single-account `DashboardProfileBatch`; one transport, status, decode, period, or account failure fails the whole batch.
- Metric cards and rank use the selected response directly. In `all`, upstream activeDays follows its chart window; never silently recompute it as lifetime days.
- Overall breakdown comes from stats inputTokens/outputTokens/cacheReadTokens/cacheWriteTokens/reasoningTokens. Missing stats categories produce an unavailable breakdown, not fabricated zeros. Sparse client buckets retain zero defaults for existing aggregation compatibility.
- TokenCategory fixes the five legend/segment order. Bar fractions use the sum of finite nonnegative categories, normalized before summation to avoid overflow. Do not replace API totalTokens with that sum.
- Profile reloads return an explicit updated/failed/superseded outcome to mutation callers; do not infer their success from a shared error cleared by another request. Re-resolve CLI context after suspended identity discovery, since Settings may have changed npx/version.
- Switching scope is a pure projection from the latest complete batch; it neither submits, fetches one remote period, nor reads/modifies autosubmit. Guard batch requests by generation and account, but do not invalidate a batch merely because selection changed.
- Status-item presentation uses the configured all/day/week/month projection from the same complete cache. It never initiates a request. The status menu exposes exactly two manual transfer actions: submit-and-refresh runs `submit` followed by one forced `fetchDashboardBatch`, and refresh-only runs `fetchDashboardBatch` alone. There is no submit-only action, because a bare `submit` leaves the visible numbers unchanged and reads as a no-op.
- Automatic paths are read-only by construction. A statistics tick, app-start synchronization, or wake evaluation must record zero `cursor login`, `submit`, `autosubmit run`, `configure`, and `disable` events. Only an explicit user action may mutate.
- Autosubmit status is status-only and event-driven: app start, a Settings window transition from hidden to visible, a manual status retry, a successful configure/disable, a successful run-now, and a resolvable npx/version change. A statistics tick, wake, or Dashboard open/close must not read it, and a status-only retry must not pull statistics alongside it.
- General Settings bindings call `updatePreferences(_:)` with the latest complete preference value. Normalize username, Tokscale version, and npx path edges, but preserve status-template bytes. This operation only saves `UserDefaults` and publishes preferences: it performs zero CLI commands and zero profile/status requests. A real case-insensitive account change invalidates the profile generation and immediately persists a snapshot without the old profiles; version/npx changes invalidate only an in-flight autosubmit-status result and retain the profile batch.
- Autosubmit status details and run-now live in Settings, with progress/success/failure feedback. Run-now uses persisted CLI settings, not unsaved form drafts.
- `applyAutosubmit(_:)` resolves the already-persisted CLI context, executes exactly one configure-or-disable command, then reads autosubmit status exactly once. It never saves a General draft, submits usage, fetches profiles, advances statistics `fetchedAt`, or dismisses Settings. If mutation succeeds but status reread fails, report that the settings were applied but status verification failed and retain the previous observed status.
- `AutosubmitStatus` reads enablement, interval, scheduler, clients, date flags/range, managed executable/version/staleness, last run milliseconds, and last error.
- Username, Tokscale version, optional `npx` path, and status-item presentation choices belong in `UserDefaults`. A separate versioned Application Support snapshot may contain mapped display data and the last observed autosubmit status; it is stale-readable state, never a configuration source. See `data-persistence.md`.
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
| Any all/week/month member fails | Throw the member error and publish no partial `DashboardProfileBatch` |
| Batch scopes or usernames differ | Reject as invalid response before the view model can publish |
| Profile HTTP 404 | `profileNotFound` |
| Other non-2xx response | Preserve HTTP status in `server(statusCode:)` |
| Missing/non-executable `npx` | `TokscaleCLIError.missingNpx`; an explicit Cursor login shows terminal fallback without launching a process |
| Arbitrary npm specifier or shell-shaped version | `invalidVersion` before process launch; never reproduce unsafe text in the Cursor terminal fallback |
| Interval outside 1...525600 minutes | `invalidInterval` |
| Unknown/shell-shaped client identifier | `invalidClient` |
| Impossible or reversed date range | `invalidDateFilter` |
| CLI non-zero exit | Surface exit code and at most 4,000 characters of stderr/stdout; only the exact temporary `autosubmit enable` launchd signature above may perform its bounded cleanup and retry |
| Compatibility `launchctl bootout` non-zero exit | Stop before Tokscale state cleanup or retry and surface a launchd compatibility-cleanup error with sanitized diagnostics |
| Compatibility Tokscale `autosubmit disable` non-zero exit | Stop before retry and surface a compatibility-state-cleanup error with sanitized diagnostics |
| CLI timeout | Terminate the child and surface `ProcessRunnerError.timedOut` |
| Invalid status JSON | `invalidStatusJSON`, without changing autosubmit |
| General username changes account | Hide and remove old-account profiles immediately; issue no request from the preference setter |
| General version or npx path changes | Reject a late status result from the old context; retain profile cache and `fetchedAt` |
| Autosubmit mutation fails | Do not read status; preserve the editable draft and show the mutation error |
| Autosubmit mutation succeeds but status read fails | Preserve old observed status and statistics; report applied-but-unverified feedback |
| Invalid pricing-list JSON/path | Fail loading; do not guess the default directory |
| Missing custom-pricing file | Show an addable empty state; create only on explicit save |
| Malformed custom-pricing JSON/models | Block writes and preserve the original bytes |
| File changed since load | Abort with a reload-required conflict; never overwrite external edits |
| Unknown/degraded dry-run output | Preserve details and show indeterminate/partial, never a clean pass |

### 5. Good / Base / Bad Cases

- Good: one dashboard refresh requests all/week/month, derives day from that same week payload, validates one username, and publishes all four scopes together.
- Bad: requesting `day`, calculating local week boundaries, or showing lifetime cached totals beneath a selected week tab.
- Good: `npx --yes tokscale@4.15.0 autosubmit enable --interval 120m --client codex --week` is built as individual arguments, then status is re-read.
- Base: app start fetches one complete batch and reads autosubmit status once; opening the panel afterwards performs neither and only shows the cached batch.
- Good: editing a status-text template publishes it from the existing complete cache without any command or request; applying autosubmit records `configure,status` or `disable,status` and leaves profile freshness unchanged.
- Bad: route General edits through autosubmit Apply, refresh profiles after autosubmit configuration, overwrite a dirty autosubmit draft with a late status, or keep another account's cached totals visible.
- Bad: interpolating `"npx tokscale@\(version) ..."` into a shell, accepting `latest;rm`, reading token files, or writing LaunchAgent/settings JSON from TokChan.


### Convention: Settings Scene Window Invocation

The SwiftUI `Settings` scene remains the sole settings-window owner. The AppKit status menu activates the application and first invokes the main menu's standard Command-Comma Settings command. If unavailable, it sends `showSettingsWindow:` through the responder chain and then `showPreferencesWindow:` only when unhandled. Keep command invocation and selector dispatch injectable so tests assert precedence and fallback without opening a real window; never locate the window by title or recreate Settings inside the popover.

### 6. Tests Required

- Verify exact URL period/username encoding, revalidation policy, finite timeout, and rejection of mismatched response scope.
- Assert one batch makes exactly three remote requests, derives day from week, rejects mixed accounts/scopes, and throws when any one request fails.
- Assert five-category fractions, empty values, malformed values and bundled icon resolution.
- Decode current and sparse public profile fixtures; assert grouped client/model totals, percentages, and token-descending order.
- Decode current and sparse autosubmit JSON; assert defaults and date summary.
- Assert every command's exact argument suffix and rejection of invalid version, client, interval, and dates. Cursor login must launch exactly once through the resolved npx URL with `cursor login`, never `/bin/sh`.
- Assert ordinary autosubmit configuration succeeds without launchctl; the exact four-signal defect orders `enable → /bin/launchctl bootout gui/<effective-uid>/ai.tokscale.autosubmit → TOKSCALE_AUTOSUBMIT_SKIP_SCHEDULER=1 autosubmit disable → enable → status`; removing any one signal performs no cleanup; launchd cleanup, state cleanup, and retry failures stop without further retry; and the scheduler-skip environment override appears only on the recovery-disable child process.
- Execute a fixture `npx` with an `/usr/bin/env` shebang; assert sibling runtime resolution through the prepended child `PATH`.
- Locator unit tests must inject or clear fixed system candidates; an empty `PATH` alone does not isolate Homebrew or `/usr/local` tools installed on CI runners. Cover explicit override/PATH/fixed precedence; every supported manager's default and absolute environment-root layout; selected/default preference; strict stable semantic sorting; deterministic cross-manager order; excluded shims, multishells and caches; broken aliases; unsafe roots/config tokens; and directory or non-executable impostors.
- Settings tests must cover automatic/custom/fallback/unavailable presentation, including whether override controls start collapsed or expanded; locator tests separately prove executable discovery and precedence.
- Custom-pricing file tests use temporary directories and cover missing/malformed files, add/edit/delete, zero versus nil, aliases, unknown/tier field preservation, duplicate IDs, and external-change conflicts.
- Fixture tests cover legacy excluded-unpriced output, current zero-cost unpriced output, all-unpriced zero summaries, no data, degraded sources, ANSI output, and unknown formats. A fake runner must assert the exact `pricing list-overrides --json` and `submit --dry-run` suffixes and prove no real submit command runs.
- With fake services, assert app start performs exactly one batch `fetch` and one `status` and zero mutations; assert a background tick and a wake evaluation perform zero `status` and zero mutations; assert panel open/close performs neither. Manual submit-and-refresh orders `submit` before a forced batch; run-now orders `run` before batch/status reload; a status-only retry records exactly one `status` and zero fetches. Explicit Cursor login records exactly one login and zero sync/submit/fetch/status/configure/disable/run follow-ups; duplicate and conflicting explicit actions are rejected, and missing npx, invalid version, nonzero exit, and timeout remain recoverable.
- Assert General preference updates normalize/persist values with zero configure/disable/status/submit/fetch events; account changes synchronously clear persisted profiles and reject late generations, while version/npx changes preserve profiles and reject late status results.
- Assert autosubmit Apply records exactly `configure,status` or `disable,status`, preserves profile `fetchedAt`, stops before status on mutation failure, and reports partial success without replacing cached status on status failure.
- Test autosubmit draft synchronization: late status initializes a pristine draft, never overwrites a dirty draft, and successful confirmation replaces the draft and clears dirty state.
- UI smoke tests must use `--ui-testing` fixture dependencies and never access the network, `npx`, or `launchd`; verify General/About have no shared Save action and only Autosubmit exposes its scoped Apply action.

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

## Scenario: First-use onboarding orchestration

### 1. Scope / Trigger

Use this contract when changing the dashboard's first-use username discovery, initial profile verification, zero-usage presentation, or first submit action. The onboarding is a projection of the current account and complete dashboard batch, not a separately persisted lifecycle.

### 2. Signatures

```swift
enum FirstUseOnboardingState: Equatable {
    case discoveringIdentity
    case usernameEntry(message: String?)
    case verifying(username: String)
    case firstSubmission(username: String, message: String?)
    case submitting(username: String)
    case hidden
}

@MainActor
extension DashboardViewModel {
    func discoverIdentity() async
    func saveAndVerifyUsername(_ username: String) async
    func editOnboardingUsername()
    func submitFirstUsage() async
}
```

### 3. Contracts

- Do not persist an onboarding-complete flag. Empty username enters username setup; a complete same-account `.all.totalTokens > 0` batch hides onboarding; a complete zero-token batch shows first submission.
- With no saved username, launch directly into editable username setup and execute zero `whoami` calls. Only `discoverIdentity()` may invoke `whoami`, after the user clicks “识别本机登录”. A successful discovery saves the normalized username before exactly one complete-batch verification; failure returns to editable setup with recoverable feedback. Duplicate discovery clicks start no second process, and a Settings username or CLI-context edit that wins while `whoami` is suspended must not be overwritten by the late result or error.
- Manual username confirmation uses `updatePreferences(_:)` for normalization, persistence, cache isolation, and generation invalidation, then forces exactly one complete profile batch. Blank input starts no service work.
- On first verification only, typed `TokscaleAPIError.profileNotFound` means no submitted profile and advances to first submission. Other API failures stay recoverable in username setup. Never classify by matching localized error text.
- First submission performs exactly one `submit` followed by exactly one forced complete batch for the same captured username. If the username changes while submit is suspended, the old operation must not fetch for or mutate the new account.
- Submission hides onboarding only after a same-account complete batch reports `.all.totalTokens > 0`. Zero Tokens, 404, or delayed server visibility keeps step two visible with retry/edit guidance and never auto-submits again.
- While onboarding discovery, verification, or submission is active, disable both status-menu transfer actions through the shared operation-busy projection. Keep ordinary loaded-dashboard refresh, stale-cache retention, and diagnostics semantics unchanged.
- Render onboarding inside the existing 380×680 Dashboard root with native controls and local card backgrounds. AppKit's `NSPopover` remains the sole root-background owner.

### 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Empty saved username at launch | Show editable username setup; execute zero `whoami` calls |
| User-triggered `whoami` succeeds | Save discovered username and verify one complete batch |
| User-triggered `whoami` or CLI context fails | Show manual username entry with recoverable feedback |
| Manual username is blank | Keep step one; no save, fetch, or submit |
| First verification returns positive all Tokens | Hide onboarding and show Dashboard |
| First verification returns zero all Tokens or typed 404 | Show first-submission step |
| First verification returns transport/server/decode error | Keep username entry and allow retry |
| First submit fails | Keep step two and surface the submit error |
| Submit succeeds, then fetch is zero/404/fails | Keep step two with accurate post-submit feedback |
| Username changes during discovery or submit | New account wins; stale operation does not fetch or publish |
| Ordinary loaded-account refresh fails | Preserve old batch and normal retry/diagnostic behavior |

### 5. Good / Base / Bad Cases

- Good: an empty first launch performs no identity lookup; clicking “识别本机登录” records one `whoami`, fetches one complete batch, and either opens the Dashboard or shows step two.
- Base: a username with no public usage receives a zero batch or 404 and can submit once, edit the username, or retry later.
- Bad: store `hasCompletedOnboarding`, treat nonempty clients as completion, parse `profileNotFound` from text, reuse normal combined-refresh banners inside onboarding, or loop submit until Tokens appear.

### 6. Tests Required

- Assert initial state from empty preferences, positive complete cache, zero complete cache, and configured account without a complete cache.
- Assert launch with an empty username records zero `whoami`; explicit discovery covers success, failure, duplicate rejection, and the race where Settings changes username or CLI context while `whoami` is suspended.
- Assert trimmed manual save, blank rejection, positive/zero/404/error verification, and exactly one complete fetch.
- Assert first submission orders `submit,fetch`, rejects duplicates, handles submit/fetch errors, remains visible after zero/404, and ignores an account switch during suspended submit.
- Assert normal statistics retry can transition a verified zero account to step two without changing loaded-account stale-cache semantics.
- Render both onboarding steps at 380×680 in light and dark appearances and provide stable accessibility identifiers for the username, website, submit, edit, progress, and feedback controls.

### 7. Wrong vs Correct

#### Wrong

```swift
if loadErrorMessage?.contains("未找到") == true {
    firstUseOnboardingState = .firstSubmission(username: username, message: nil)
}
```

Localized strings are presentation, not a stable error contract, and this can misclassify unrelated failures.

#### Correct

```swift
switch profileReloadResult {
case .profileNotFound:
    firstUseOnboardingState = .firstSubmission(username: username, message: nil)
case .failed(let message):
    firstUseOnboardingState = .usernameEntry(message: message)
default:
    reconcileOnboardingWithCompleteCache(username: username)
}
```
