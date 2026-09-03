# Bootstrap Task: Fill Project Development Guidelines

**You (the AI) are running this task. The developer does not read this file.**

The developer initialized Trellis in a repository that will become a simple SwiftUI macOS application. The generated fullstack `backend` / `frontend` spec scaffold does not match the intended project shape and must be replaced with SwiftUI-focused guidance.

## Goal

Populate `.trellis/spec/` with practical conventions for future AI coding sessions working on the TokChan macOS SwiftUI app.

## Status

- [x] Replace generated backend/frontend scaffold with macOS SwiftUI spec layer
- [x] Document that no app source exists yet and current rules are baseline conventions
- [x] Add SwiftUI-oriented guidelines for structure, views, state, persistence, networking, quality, and testing
- [ ] Revisit these specs after the first Xcode project/app skeleton exists and add real code examples

## Spec files to populate

| File | What to document |
|------|------------------|
| `.trellis/spec/macos/index.md` | SwiftUI spec index and default technology choices |
| `.trellis/spec/macos/directory-structure.md` | Xcode project layout, app target, feature folders, shared services |
| `.trellis/spec/macos/swiftui-guidelines.md` | SwiftUI view composition, navigation, previews, accessibility |
| `.trellis/spec/macos/state-management.md` | Local state, observable view models, environment, service injection |
| `.trellis/spec/macos/data-persistence.md` | Choosing UserDefaults, files, SwiftData/Core Data, Keychain |
| `.trellis/spec/macos/networking-guidelines.md` | External API boundaries, async/await, decoding, testing |
| `.trellis/spec/macos/quality-guidelines.md` | Swift style, error handling, concurrency, dependencies |
| `.trellis/spec/macos/testing-guidelines.md` | Unit tests, UI tests, previews, xcodebuild validation |

## Acceptance criteria

- `.trellis/spec/backend/` and `.trellis/spec/frontend/` are not used for this repository's default guidance.
- `get_context.py --mode packages` reports a macOS-oriented spec layer instead of web/backend layers.
- The bootstrap task metadata points at `.trellis/spec/macos/`.
- The specs do not claim a backend or web frontend exists.
- The specs clearly state that real examples must be added after source files exist.

## Completion

When the developer confirms the current baseline is sufficient, run:

```bash
python3 ./.trellis/scripts/task.py finish
python3 ./.trellis/scripts/task.py archive 00-bootstrap-guidelines
```
