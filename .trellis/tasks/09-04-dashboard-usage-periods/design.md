# Technical design

## Data contracts

Introduce a typed ProfilePeriod with all/week/month. Extend TokscaleAPIService.fetchProfile with period, encode it through URLComponents query items, and decode returned period/dateRange plus five stats token components. DashboardData remains a mapped, Codable display snapshot: identity, period, dateRange, stats breakdown and existing client/model groups. Keep aggregation over returned contributions only; card values and rank always come from the same response. Validate requested/returned period agreement rather than silently rendering all for a requested finite period. Update API fakes and previews.

## State and concurrency

DashboardViewModel owns selectedPeriod (initial all), period-aware profile caches keyed by username/period, and request generations. A selection changes visible profile to that exact cached entry or loading state and fetches the selected scope without invoking any CLI mutation. Late requests can only update their own cache; they cannot replace a different visible selection. Account changes invalidate account-bound entries. Preserve selected scope across refresh, run-now and settings profile reloads; guard each result against current account/scope and in-flight generation. Keep autosubmit state independent of scope selection.

## Cache compatibility

Persist only mapped display data with explicit schema/period metadata, never raw history. An incompatible old snapshot is disposable and must not cause invented zeros or appear under another range. Use atomic writes and the existing cache boundary. Retain the current snapshot shape where possible and add versioning/optional mapped per-period entries only as needed; identity and scope checks apply to disk and memory hydration.

## View composition

Use a fixed outer VStack at current 380×680 dimensions. Header and bounded load/operation feedback, native segmented Picker, metrics and breakdown view stay outside scrolling. Place only client cards in a ScrollView/LazyVStack using remaining height; keep client section heading and footer fixed. Long status text must be bounded and expandable through settings/detail help so it cannot consume the client viewport.

Build the breakdown as a horizontal clipped bar with five stable shades and a compact wrapping legend. Values use existing compact formatters. Fractions use nonnegative finite component values divided by their sum, treating zero as no segment; show all five legend entries and never invent equal-width data. Preserve returned totalTokens in its metric even if upstream component sum differs.

Client card owns local expanded state; render prefix(5) by default and all on expansion. Identity includes period so selection resets expansion. Map upstream client IDs and aliases to named bundled assets, including codex→openai; use a fallback for unknown IDs. Model sorting stays token-descending with stable ID tie-breaks.

## Autosubmit settings

Extract/rehome existing status content into the settings autosubmit page, keeping status, interval, scheduler/version/staleness, selected clients/date filter, executable, last run/error and Run Now. Run against persisted configuration with explanatory help; do not silently save edited drafts. Keep asynchronous progress, success and failures visible in settings. Preserve current Save behavior and native Settings window invocation. Profile data failure and autosubmit failure should be presented in their relevant surfaces.

## Resources

Copy every client-* image from the official assets directory, retain provenance and applicable upstream notices. Use asset catalogs for rendering; preserve originals where WebP conversion to a build-supported raster format is needed. Ensure original copies are also bundled without duplicated resource names. Do not require runtime remote loading. No new package dependencies.

## Risks and rollback

Main risks are scope races, stale cache labeling, loss of settings feedback, and fixed-height layout overflow. Tests exercise these behaviors. Reverting this task's code/resources restores the previous layout; cache remains disposable and server/CLI contracts are unchanged.

## Cache-first revision

Snapshot now stores profiles: [CachedDashboardProfile] plus selectedPeriod, migrating the old single-profile shape. load() requests only missing resources and a cached selection returns immediately. Explicit refresh keeps other scope entries intact. isLoading combines profile fetch, identity/status initialization and operations for one header button. Visible day requests wire period=week and projects dateRange.end from daily contributions, with nil rank; the server remains the date authority.
