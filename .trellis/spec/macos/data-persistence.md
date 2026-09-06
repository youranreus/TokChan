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

## Scenario: Dashboard snapshot cache

### 1. Scope / Trigger

Use this contract when changing dashboard loading, profile display models, autosubmit status fields, or local caching. The cache exists to eliminate empty loading states when the menu panel is reopened; it is never the source of truth for Tokscale configuration.

### 2. Signatures

```swift
struct DashboardCacheSnapshot: Codable, Equatable {
    static let currentSchemaVersion: Int
    let schemaVersion: Int
    let username: String?
    let generation: UInt64
    let profile: DashboardData? // Compatibility field for the previous file format.
    let profiles: [CachedDashboardProfile]
    let selectedPeriod: ProfilePeriod
    let autosubmit: AutosubmitStatus?
    let autosubmitObservedAt: Date?
    let fetchedAt: Date? // Present only for a complete all/day/week/month batch.
    let savedAt: Date
}

protocol DashboardCacheStoring {
    func load() -> DashboardCacheSnapshot?
    func save(_ snapshot: DashboardCacheSnapshot) throws
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
- On panel open, show cached values first. A complete batch is fresh for 300 seconds; a missing, expired, or clock-rollback snapshot starts one read-only whole-batch refresh without clearing visible data. Scope switches consume the in-memory batch and never start independent scope requests.
- Statistics publish only after all remote inputs succeed. A failed or superseded batch preserves the previous map and `fetchedAt`. Explicit submit/run/settings operations force a new whole-batch read after the mutation and cannot reuse a pre-mutation request.
- The 30-second failure cooldown applies only to automatic triggers. A user-initiated error-state retry is read-only, forces a new whole batch immediately, and never runs submit.
- Autosubmit status has its own `autosubmitObservedAt` and error path. Status-only saves and selected-scope saves must not advance statistics `fetchedAt`.
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
- TTL/cooldown: assert `<300s` skips statistics, `>=300s` refreshes, clock rollback refreshes, and automatic failures retry no sooner than 30 seconds.
- Batch failure: fail any one remote scope and assert every cached scope and the old `fetchedAt` remain.
- Concurrency: assert duplicate triggers coalesce and old account/generation results cannot publish.
- Lifecycle: assert a visible panel ticks and a hidden panel schedules no additional reads.
- Write failure: assert fresh memory data remains usable and the previous on-disk snapshot is preserved.

### 7. Wrong vs Correct

#### Wrong

```swift
func load() async {
    profileState = .loading
    autosubmitState = .loading
    // Existing content disappears every time the popover opens.
}
```

#### Correct

```swift
func load() async {
    // Keep a loaded snapshot visible while freshness is evaluated.
    async let statistics = reloadProfiles(force: false, automatic: true)
    async let status = reloadAutosubmitIfNeeded()
    _ = await (statistics, status)
}
```

### Cache-first regression requirements

Round-trip a complete all/day/week/month batch through JSON, reconstruct the view model, and select every scope without requests. At 299 seconds assert no statistics request; at 300 seconds assert one read-only batch. Submit once and assert submit precedes one whole-batch fetch. Decode previous single-profile/multi-profile snapshots as stale migration input. Do not display background refresh narration or make the submit button spin for a cached silent read.
