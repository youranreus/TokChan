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
