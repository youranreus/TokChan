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
    let profile: DashboardData? // Compatibility field for the previous file format.
    let profiles: [CachedDashboardProfile]
    let selectedPeriod: ProfilePeriod
    let autosubmit: AutosubmitStatus?
    let savedAt: Date
}

protocol DashboardCacheStoring {
    func load() -> DashboardCacheSnapshot?
    func save(_ snapshot: DashboardCacheSnapshot) throws
}
```

The production implementation is `FileDashboardCacheStore`; tests use an in-memory implementation.

### 3. Contracts

- Store one compact JSON file at `~/Library/Caches/com.youranreus.TokChan/dashboard-snapshot.json` (or the equivalent user caches URL returned by Foundation).
- Cache only mapped `DashboardData`, `AutosubmitStatus`, and `savedAt`; do not cache raw contribution history, credentials, environment variables, or autosubmit configuration as a second source of truth.
- `DashboardData.period` remains required. Migrate the preceding single-profile file into a one-entry map when profiles/selectedPeriod are absent. Restore the persisted selection when present. Truly unscoped legacy profiles are incompatible and disposable.
- Entries are scope-specific and checked against the current username. Persist the complete map and selected scope after reads and cached selection changes; restore all scopes on relaunch. Each CachedDashboardProfile retains its own savedAt. Account changes invalidate the map; submissions update the selected scope without deleting the others. Keep request generation guards.
- Hydrate `DashboardViewModel` synchronously from the small snapshot during initialization so its first rendered state can already be `.loaded`.
- On panel open, perform profile/status reads only for missing cached resources. A scope switch with a matching cache performs no request. Explicit submit refreshes the current scope; preserve other scope entries. Opening or closing a panel never invalidates the map.
- If the selected username differs from the cached profile username, ignore the cached profile. Autosubmit status remains machine-local and may still be displayed.
- Use atomic file replacement for writes. A cache write failure must not fail a successful Tokscale operation.

### 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Cache file missing | Return `nil`; perform normal first-load placeholders and online reads |
| Cached scope differs from selected scope | Keep identity only; load the selected scope, never show mismatched metrics |
| Cache JSON corrupt or schema-incompatible | Return `nil`; never crash or block online loading |
| Cached username differs from preference | Ignore cached profile; do not show another user's totals |
| Background refresh fails with valid cache | Keep cached content and show a non-destructive background error |
| Fresh profile or status succeeds | Update UI and atomically replace the available snapshot fields |
| Cache directory/write fails | Keep fresh UI result; do not convert the operation to failure |

### 5. Good / Base / Bad Cases

- Good: panel reopens or the app relaunches, every cached scope renders immediately with zero network requests. The header submit button is the single loading indicator when a missing scope is fetched or a manual submission runs.
- Base: first launch has no snapshot, so only the missing resources show loading placeholders until their first success.
- Bad: setting both states to `.loading` on every panel open, caching API credentials, or treating a corrupt optional cache as a fatal load error.

### 6. Tests Required

- File-store round trip: save a complete snapshot and assert decoded equality.
- Legacy migration: remove required period metadata and assert snapshot decoding fails.
- Corruption: write invalid JSON and assert `load()` returns `nil` without throwing.
- View-model hydration: construct with a snapshot and assert profile/status are `.loaded` before calling `load()`.
- Background failure: make API and CLI reads fail, then assert cached states remain `.loaded` and a refresh error is exposed.
- Fresh load: assert successful profile/status reads populate the cache.

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
    if profileState.loadedValue == nil { profileState = .loading }
    if autosubmitState.loadedValue == nil { autosubmitState = .loading }
    isRefreshing = true
    // Cached values remain visible while fresh reads run.
}
```

### Cache-first regression requirements

Round-trip all/day/week/month through JSON, reconstruct the view model, select every scope and reopen with load(); assert no API/CLI calls. Submit once and assert submit precedes one selected-scope fetch while all cached entries remain. Decode previous single-profile snapshots and verify migration. Do not display background refresh narration or a second spinner.
