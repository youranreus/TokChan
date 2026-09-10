# Design：客户端列表展示过滤配置

## 1. Architecture and boundaries

This feature remains a local presentation preference. It spans four existing boundaries:

1. `UserPreferences` / `UserDefaultsPreferencesStore` own durable settings.
2. `DashboardViewModel` owns the union of client IDs available from the in-memory four-period cache.
3. A small pure display-filtering helper derives visible client/model values without mutating `DashboardData` or the snapshot cache.
4. `SettingsView` edits preferences immediately; `DashboardView` renders the derived list and distinguishes source-empty from filter-empty states.

No Tokscale API, CLI, cache schema, aggregation, status-item rendering, or network behavior changes.

## 2. Preference contract

Extend `UserPreferences` with:

- `hideZeroCostModels: Bool` — default `false`.
- `hiddenClientsEnabled: Bool` — default `false`.
- `hiddenClientIDs: Set<String>` — default empty.

`UserDefaultsPreferencesStore` persists the booleans and a stable sorted string array. Missing keys use the defaults above so upgrades preserve current behavior. Preference normalization trims client IDs, drops empty IDs, and deduplicates them without affecting unrelated fields.

All controls reuse the existing immediate `DashboardViewModel.updatePreferences(_:)` path. Updating these fields must not trigger account invalidation, Tokscale requests, CLI operations, or cache writes.

## 3. Candidate client data flow

`DashboardViewModel.availableClientIDs` is derived from:

- every `ClientUsageGroup.id` in every currently loaded `cachedProfiles` entry for all/day/week/month; and
- every persisted `hiddenClientIDs` value.

The result is deduplicated and sorted deterministically for Settings. Including persisted selections keeps temporarily absent clients editable. A successful statistics batch naturally refreshes the candidate union through the existing `cachedProfiles` publication.

The candidate union itself is derived state and is not stored as another source of truth.

## 4. Display filtering contract

Introduce a pure helper at the Dashboard feature layer that accepts source clients and preferences and returns a new client array:

1. If `hiddenClientsEnabled` is true, remove clients whose IDs occur in `hiddenClientIDs`; otherwise retain all clients.
2. If `hideZeroCostModels` is true, copy each retained client with only models whose `cost != 0`; otherwise retain its model array.
3. Preserve client ordering, model ordering, client totals, percentage, and all source data.
4. Never remove a client merely because model filtering leaves it with no visible models.

The zero-cost comparison is exact because the product setting explicitly targets models whose represented cost is zero. Negative or positive nonzero values remain visible.

`DashboardView` renders the derived clients. Empty-state handling distinguishes:

- source `profile.clients.isEmpty`: existing “no submitted client/model details” copy;
- source nonempty but derived clients empty: copy explaining that display settings hid all clients.

A client with no visible models still shows its client summary card.

## 5. Settings UI

Add a native `TabView` item named “展示配置”, using an SF Symbol and a grouped `Form`.

The page contains:

- a model section with the “隐藏开销为 0 的模型” toggle;
- a client section with the “隐藏指定客户端” master toggle;
- one native switch row per `availableClientIDs` entry, using `.toggleStyle(.switch)` and `ClientIcon`;
- an explanatory empty state when no client candidates exist.

The master enable control and each client membership row use native switch semantics. Candidate rows (including the no-candidate state) render only while the master switch is enabled; disabling it collapses the list without mutating `hiddenClientIDs`, so reopening restores prior selections. Add stable accessibility identifiers to the page and key controls.

### Client icon catalog and presentation

`ClientIcon` is the shared registry and presentation component for Dashboard and Settings. Its authoritative ID coverage follows Tokscale's current `SUPPORTED_CLIENT_TYPES`. Compatibility IDs for the same product may point to one asset (`codex` → `client-openai`, `kilo` → `client-kilocode`, `antigravity-cli` → `client-antigravity`, Devin variants → `client-devin`); distinct products use distinct assets.

Every rendered icon receives one macOS-app-style rounded mask and a subtle shadow in `ClientIcon`, so all call sites remain visually consistent. `codebuddy` resolves to dedicated `client-codebuddy`, separate from `client-codebuff`. For externally sourced assets, retain originals and record exact URLs and checksums in provenance metadata. Extend asset tests to verify the full authoritative mapping and bundle loading.

## 6. Compatibility and migration

- Existing installs have no new UserDefaults keys and therefore render exactly as before.
- No dashboard snapshot schema change is needed because raw dashboard data remains unchanged.
- Unknown or temporarily absent selected client IDs stay persisted and remain candidates.
- No external dependency or deployment-target change is required.

## 7. Testing strategy

- Preferences store tests: full round trip, missing-key defaults, deterministic hidden-ID persistence/normalization.
- Pure filter tests: default pass-through, zero-cost model filtering, client master switch behavior, retained ordering/totals, combined filters, and client retention when every model is removed.
- View-model tests: candidate union across four cached periods plus persisted absent selections; preference-only edits issue no API/CLI calls.
- UI/layout coverage: Settings exposes the new native tab/page and key controls; Dashboard filter-empty copy differs from source-empty copy.

## 8. Risks and rollback

- Risk: putting filtering into `DashboardData` aggregation would contaminate totals/cache. Mitigation: keep a pure presentation projection after data loading.
- Risk: deriving candidates from only `profileState` would lose clients from other periods. Mitigation: derive from `cachedProfiles` plus persisted selections.
- Risk: Set persistence order is unstable. Mitigation: save a sorted array and sort again for UI.

Rollback is limited to removing the three preference fields/keys, the pure helper, and the Settings/Dashboard presentation wiring. Existing stored keys can safely remain ignored by an older build.
