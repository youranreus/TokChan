# Data Persistence

## Default storage decision

No persistence requirement exists yet. Choose the smallest durable storage that satisfies the feature.

## Decision guide

- Use in-memory state for temporary UI data.
- Use `UserDefaults` for small preferences only.
- Use local JSON files for simple user-created records when relational querying is unnecessary.
- Use SwiftData or Core Data only when the app needs structured persistence, relationships, querying, migration, or larger datasets.
- Store secrets in Keychain, not `UserDefaults` or plain files.

## Implementation rules

- Keep persistence code behind a service boundary under `Shared/Services/`.
- Use explicit model types for encoded data.
- Handle decode and migration failures deliberately; do not silently discard user data unless the PRD allows it.
- Keep persistence operations off SwiftUI `body` computation.

## Avoid

- Do not add a database before the app has data that needs one.
- Do not let views know file paths, database contexts, or serialization formats directly.

## Scenario: Status-item presentation preferences

Keep `statusTextEnabled`, `statusTextTemplate`, and `statusTextPeriod` in `UserPreferences` through `UserDefaultsPreferencesStore`; they are small user choices, not dashboard cache fields. Missing keys decode as `false`, `{token} · {cost}`, and `.day`; an unknown period raw value also falls back to `.day`. Preserve template bytes as entered, including empty strings and unknown placeholders. Persist General control changes immediately through `DashboardViewModel.updatePreferences(_:)`; this local update must not submit usage, configure autosubmit, or fetch profile/status data. Round-trip all keys in tests and assert old stores remain compatible.

## Scenario: Dashboard display-filter preferences

### 1. Scope / Trigger

Use this contract when adding or changing local preferences that hide dashboard client or model detail. Display filtering is a projection over loaded data; it must not become part of Tokscale aggregation or the dashboard snapshot schema.

### 2. Signatures

```swift
struct UserPreferences {
    var hideZeroCostModels: Bool       // default false
    var hiddenClientsEnabled: Bool     // default false
    var hiddenClientIDs: Set<String>   // default []
}

enum DashboardDisplayFilter {
    static func clients(
        from sourceClients: [ClientUsageGroup],
        preferences: UserPreferences
    ) -> [ClientUsageGroup]
}

@MainActor
extension DashboardViewModel {
    var availableClientIDs: [String] { get }
}
```

### 3. Contracts

- Persist the three fields through `UserDefaultsPreferencesStore`. Save `hiddenClientIDs` as a sorted string array; trim whitespace, discard empty IDs, and deduplicate on construction/normalization.
- Missing keys decode as disabled switches and an empty set, preserving pre-feature display after upgrade.
- `availableClientIDs` is derived from the union of every in-memory all/day/week/month cached profile plus persisted hidden IDs. Sort the result for stable Settings presentation; do not persist a second candidate-list source of truth.
- Client filtering applies only when `hiddenClientsEnabled` is true. Model filtering removes only models whose `cost == 0`, preserves negative and positive nonzero costs, and never removes a client merely because its projected model list is empty.
- Preserve client/model order, client totals, percentages, metrics, status-item text, and the raw cache. Ordinary control changes persist immediately through `updatePreferences(_:)` and must issue no API/CLI call or cache write.
- Dashboard source-empty and display-filter-empty states are distinct. Settings uses a native `TabView` page; the master enable control and each independent client membership choice use native switch semantics with `ClientIcon`. Do not model persistent settings as modifier-key `List` selection. Render candidate rows only while the master switch is enabled; disabling it collapses the list without clearing `hiddenClientIDs`.

### 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| New UserDefaults keys missing | Show every client/model; hidden-client selection is empty |
| Stored client IDs contain whitespace, duplicates, or empty values | Trim, deduplicate, and discard empties |
| Hidden IDs are absent from every current period | Keep them persisted and include them in Settings candidates |
| Client master switch is off | Preserve selections, show all clients, and collapse candidate rows in Settings |
| Zero-cost filtering removes every model under a client | Keep the client summary card with an empty model list |
| Client filtering removes every source client | Show the display-filter-empty message, not the source-empty message |
| Display preference changes | Save preferences and republish UI only; perform zero API/CLI/cache operations |

### 5. Good / Base / Bad Cases

- Good: four cached periods contribute different client IDs; Settings shows their sorted union plus one selected absent ID, and enabling both filters changes only rendered rows.
- Base: an upgraded install has none of the new keys and renders exactly the unfiltered dashboard.
- Bad: filtering `DashboardData` during aggregation, rewriting the snapshot with projected clients, using only the selected period for candidates, or clearing selections when the master switch turns off.

### 6. Tests Required

- Preferences: round-trip all fields, assert sorted array storage, and assert missing-key defaults plus client-ID normalization.
- Projection: assert default pass-through, exact-zero model removal, independent and combined client filtering, stable order/totals/percentages, source immutability, and retention of a client with no projected models.
- View model: hydrate distinct clients across all four cached periods, include persisted absent selections, and assert a display-only update records zero external events and zero cache writes.
- UI/accessibility: expose stable identifiers for the display page, master switch, and client switches; assert candidate rows collapse while disabled and reappear with retained selections after re-enabling, and distinguish source-empty from filter-empty copy.

### 7. Wrong vs Correct

#### Wrong

```swift
// This corrupts the cache/metrics boundary by treating a display preference as source data.
profile.clients.removeAll { preferences.hiddenClientIDs.contains($0.id) }
cacheStore.save(profile)
```

#### Correct

```swift
let visibleClients = DashboardDisplayFilter.clients(
    from: profile.clients,
    preferences: preferences
)
// Render visibleClients; keep profile and its cached representation unchanged.
```


## Scenario: Dashboard snapshot cache

### 1. Scope / Trigger

Use this contract when changing dashboard loading, profile display models, autosubmit status fields, or local caching. The cache exists to eliminate empty loading states when the menu panel is reopened; it is never the source of truth for Tokscale configuration.

### 2. Signatures

```swift
struct CachedDashboardProfile: Codable, Equatable {
    let data: DashboardData
    let savedAt: Date
    let source: DashboardDataMode // Missing in schema 1/2 decodes as .online.
}

struct DashboardCacheSnapshot: Codable, Equatable {
    static let currentSchemaVersion: Int // 3 since the data-source split.
    let schemaVersion: Int
    let username: String?
    let generation: UInt64
    let profile: DashboardData? // Compatibility field for the previous file format.
    let profiles: [CachedDashboardProfile]
    let selectedPeriod: ProfilePeriod
    let autosubmit: AutosubmitStatus?
    let autosubmitObservedAt: Date?
    let fetchedAt: Date? // Online-only compatibility field.
    let fetchedAtBySource: [DashboardDataMode: Date] // One entry per complete batch.
    let savedAt: Date

    func isCompleteBatch(for source: DashboardDataMode, account: String?) -> Bool
}

protocol DashboardCacheStoring {
    func load() -> DashboardCacheSnapshot?
    func save(_ snapshot: DashboardCacheSnapshot) throws
    func clear() throws
}
```

The production implementation is `FileDashboardCacheStore`; tests use an in-memory implementation.

### 3. Contracts

- Store one compact, versioned JSON file under Foundation's Application Support directory at `com.youranreus.TokChan/dashboard-snapshot.json`. The previous Caches path is a read-only migration fallback when the new file is missing or invalid.
- Cache only mapped `DashboardData`, `AutosubmitStatus`, and `savedAt`; do not cache raw contribution history, credentials, environment variables, or autosubmit configuration as a second source of truth.
- `DashboardData.period` remains required. Migrate preceding single-profile and unversioned multi-profile files for stale display, but never infer that independent legacy entries are one fresh batch. Truly unscoped legacy profiles are incompatible and disposable.
- A fresh snapshot contains exactly one entry for each of all/day/week/month, one case-insensitive username, one generation, and one shared `fetchedAt`. Duplicate/missing scopes or a missing batch timestamp are incomplete and must refresh.
- Entries are checked against the current username. Persist the complete map and selected scope after successful batch reads and cached selection changes; restore all available scopes on relaunch. Account changes invalidate the map and request generation before a new account can publish.
- Hydrate `DashboardViewModel` synchronously from the small snapshot during initialization so its first rendered state can already be `.loaded`.
- Statistics freshness is an application-level concern, not a panel-level one. One scheduler owned by the app runs `reloadProfiles(force: false, automatic: true)` regardless of popover visibility, so the status item keeps updating while the Dashboard is closed. Panel open still shows cached values first, but the popover must not start, stop, or accelerate the schedule.
- A complete batch is fresh for 300 seconds; a missing, expired, or clock-rollback snapshot starts one read-only whole-batch refresh without clearing visible data. Scope switches consume the in-memory batch and never start independent scope requests.
- Statistics publish only after all remote inputs succeed. A failed or superseded batch preserves the previous map and `fetchedAt`. Explicit submit/run operations force a new whole-batch read after the mutation and cannot reuse a pre-mutation request.
- Automatic failures back off through `[30, 60, 300]` seconds, holding at 300 once exhausted, and reset to no backoff on any success. The backoff applies only to automatic triggers, so a closed panel can never produce a permanent 30-second request storm. A user-initiated error-state retry is read-only, ignores the backoff, forces a new whole batch immediately, and never runs submit.
- An empty username makes every automatic path a silent no-op: it must not emit an invalid-username diagnostic or burn a backoff step. The scheduler simply waits one full interval.
- Autosubmit status has its own `autosubmitObservedAt` and error path, advanced only by its own status-only triggers (app start, a Settings window becoming visible, manual status retry, apply/disable, run-now, and CLI-context change). Statistics ticks, wake, and Dashboard open/close must never read it, and applying autosubmit configuration must not advance statistics `fetchedAt`.
- If the selected username differs from the cached profile username, ignore the cached profile. Autosubmit status remains machine-local and may still be displayed.
- Use atomic file replacement for writes. A cache write failure must not fail a successful Tokscale operation.

### 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Cache file missing | Return `nil`; perform normal first-load placeholders and online reads |
| Cached scope differs from selected scope | Keep identity only; load the selected scope, never show mismatched metrics |
| Cache JSON corrupt or schema-incompatible | Return `nil`; never crash or block online loading |
| New Application Support file invalid, legacy Caches file valid | Return the legacy snapshot and migrate only after a successful new-path write |
| Cached username differs from preference | Ignore cached profile; do not show another user's totals |
| Any statistics request fails | Keep every old scope and the old statistics `fetchedAt`; expose a light diagnostic |
| Complete statistics batch succeeds | Replace all four scopes in memory together, then atomically persist the versioned snapshot |
| Autosubmit status succeeds/fails | Update or retain status independently; never block a successful statistics batch |
| Cache directory/write fails | Keep fresh UI result; do not convert the operation to failure |

### 5. Good / Base / Bad Cases

- Good: a fresh complete snapshot renders every scope immediately; an expired snapshot stays visible while one silent read-only batch replaces all scopes.
- Base: first launch has no snapshot, so real loading/failure state remains until the first complete batch succeeds.
- Bad: publishing all/week/month independently, advancing `fetchedAt` on a selection/status save, deleting a readable stale batch on refresh failure, or caching credentials.

### 6. Tests Required

- File-store round trip: save a versioned complete snapshot and assert decoded equality and completeness.
- Legacy migration: decode single/multi-scope legacy snapshots as stale; remove required period metadata and assert decoding fails.
- Corruption: write invalid new JSON and assert a valid legacy-path snapshot is used; without a backup return `nil`.
- View-model hydration: construct with a snapshot and assert profile/status are `.loaded` before calling `load()`.
- TTL/backoff: assert `<300s` skips statistics, `>=300s` refreshes, clock rollback waits a full interval instead of busy-looping, automatic failures escalate 30 → 60 → 300 and hold, and any success resets the escalation.
- Batch failure: fail any one remote scope and assert every cached scope and the old `fetchedAt` remain.
- Concurrency: assert duplicate triggers coalesce and old account/generation results cannot publish.
- Lifecycle: assert the scheduler keeps refreshing while the panel is closed, that `start` is idempotent across repeated calls, that panel open/close changes no schedule, and that an empty username issues zero requests and zero diagnostics.
- Wake: assert a fresh snapshot triggers zero requests, a stale one triggers exactly one batch, a long sleep does not replay missed ticks, and a wake coinciding with the deadline still yields one batch.
- Write failure: assert fresh memory data remains usable and the previous on-disk snapshot is preserved.

### 7. Wrong vs Correct

#### Wrong

```swift
func panelDidAppear() {
    isPanelVisible = true
    startRefreshTimer()   // Freshness dies with the popover; the status item goes stale.
}
```

#### Correct

```swift
// One application-level scheduler, started once at launch and never tied to the popover.
func startBackgroundSynchronization() {
    startStatisticsSchedulerIfNeeded()
    guard !hasSynchronizedOnLaunch else { return }
    hasSynchronizedOnLaunch = true
    Task { [weak self] in await self?.load() }
}

func panelDidAppear() {
    // Visibility and banner lifetime only; no scheduling, no requests.
    isPanelVisible = true
}
```

### Cache-first regression requirements

Round-trip a complete all/day/week/month batch through JSON, reconstruct the view model, and select every scope without requests. At 299 seconds assert no statistics request; at 300 seconds assert one read-only batch. Submit once and assert submit precedes one whole-batch fetch. Decode previous single-profile/multi-profile snapshots as stale migration input. Do not display background refresh narration or make the submit button spin for a cached silent read.

## Scenario: Data-source modes, initialization, and configuration reset

### 1. Scope / Trigger

Use this contract when adding or changing the local/online dashboard data source, its persisted mode preference, the first-run mode welcome, or the TokChan configuration reset. The mode is a display-source choice; it never disables Tokscale's own autosubmit scheduler.

### 2. Signatures

```swift
enum DashboardDataMode: String, Codable, CaseIterable, Identifiable { case local, online }

struct UserPreferences {
    var dataMode: DashboardDataMode      // missing key -> .local
    var hasCompletedInitialization: Bool // missing key -> false
}

protocol PreferencesStoring {
    func load() -> UserPreferences
    func save(_ preferences: UserPreferences)
    func clear() throws
}

protocol DashboardDataReading {
    var source: DashboardDataMode { get }
    func fetchDashboardBatch(_ request: DashboardSourceRequest) async throws -> DashboardSourceBatch
}

@MainActor extension DashboardViewModel {
    func selectInitialMode(_ mode: DashboardDataMode) async
    func selectDataMode(_ mode: DashboardDataMode) async
    func refreshCurrentSourceFromPanel() async
    func resetConfiguration(disableLaunchAtLogin: () throws -> Void) async -> Bool
}
```

### 3. Contracts

- `UserPreferences.defaults` is `dataMode: .local`, `hasCompletedInitialization: false`. A missing key decodes the same way, so new installs and upgrading users both land on the mode welcome; an explicit choice is persisted and survives relaunch.
- `DashboardSourceBatch` carries `source`, optional `account`, exactly four periods, and bounded warnings. Its initializer throws `DashboardSourceError.invalidGraph` unless the periods are exactly all/day/week/month and each entry's `period` matches its key. Local batches carry `account: nil`.
- Cache entries carry `source`. Schema 1/2 decodes every entry as `.online` and never as local, so legacy snapshots cannot masquerade as local usage. `isCompleteBatch(for:account:)` requires a `fetchedAtBySource` entry, exactly four same-source periods, and — for online only — a matching account.
- Freshness, TTL, and automatic backoff are tracked per source in `fetchedAtBySource`. Switching mode restores that mode's own `cacheSavedAt` and cached profiles; it does not clear the other source's validity.
- A panel refresh routes by mode: local reads the Tokscale graph immediately, online keeps submit-then-refetch. The status menu's online-only actions always pass `source: .online` explicitly, so they update the online cache without changing the visible mode, panel, or status-item title.
- Entering local mode from the welcome page completes initialization immediately and does not require a successful read; online completes it only through the existing account flow. `markInitializationComplete()` is the single writer, and every automatic path stays a no-op until it is set.
- `resetConfiguration` stops the scheduler, invalidates profile/status/cursor requests, then clears preferences, the current Application Support snapshot, and the legacy Caches snapshot before returning to `.modeSelection`. All of these are protocol obligations (`clear()`); a store that cannot clear must throw rather than silently succeed.
- Any account change persists a snapshot without the previous account's online profiles, including while the visible source is local. Account identity is never required for a local batch, and local mode never fabricates a username or rank.

### 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Mode key missing, or upgrading user with no initialization key | Show `.modeSelection`; keep existing username and caches |
| Local choice with no Tokscale CLI or failing graph | Enter the panel; the read failure is retryable in-panel and never blocks initialization |
| Batch periods incomplete, extra, or mismatched | Throw `invalidGraph`; publish nothing |
| Empty graph export | Valid zero-usage batch, not an error |
| Malformed JSON, non-finite/negative value, or summary/contribution mismatch | Throw; never report zero usage, and keep the previous cache |
| Timezone command fails or returns an unsupported zone | `invalidTimezone`; never guess the host timezone |
| Explicit online action while in local mode | Update only the online cache and diagnostics; keep mode, panel, and status title |
| Mode switch during a running explicit operation | Ignored |
| Late result after mode switch, account change, CLI-context change, or reset | Finish as superseded; publish nothing |
| Reset partially fails | Return `false`, keep a retryable error, and never report success |

### 5. Good / Base / Bad Cases

- Good: an uninitialized install shows the mode welcome; choosing local hides onboarding and starts one graph read, and a failing read still leaves the panel usable.
- Base: an existing online install upgrades, sees the mode welcome once, keeps its username and cache, and afterwards switches modes from either the status menu or Settings with the same persisted preference.
- Bad: treating schema 2 data as local usage, requiring a username for a local batch, publishing an online menu read into the local panel, reusing one `fetchedAt` for both sources, or calling `save(.defaults)` and calling it a reset while the disk snapshot survives.

### 6. Tests Required

- Preferences round trip for both new keys, missing-key defaults (`.local`, `false`), and `clear()` removing every owned key.
- Cache: schema 1/2 migration forces `.online`, `isCompleteBatch(for:account:)` rejects wrong-account and mixed-source batches, and `clear()` removes current and legacy files.
- Sources: assert four-period aggregation, midnight/empty-range boundaries, `invalidGraph` on malformed or inconsistent payloads, and zero published usage on failure.
- Mode coordination: local panel refresh records zero submits and zero public-API calls; online keeps submit-before-fetch; explicit online actions in local mode record one online read and leave visible state untouched.
- Races: a suspended local read that resumes after a CLI-context change, an account change, or a reset publishes nothing, and a reset cannot be revived by a late autosubmit-status read.
- Reset: assert preferences, cache, in-memory profiles, initialization, and launch-at-login are all cleared; a failing clear keeps state and can be retried.

### 7. Wrong vs Correct

#### Wrong

```swift
// One freshness value for two sources: switching modes shows the other source's age.
self.cacheSavedAt = fetchedAt
```

#### Correct

```swift
self.fetchedAtBySource[source] = fetchedAt
if source == self.preferences.dataMode { self.cacheSavedAt = fetchedAt }
```
