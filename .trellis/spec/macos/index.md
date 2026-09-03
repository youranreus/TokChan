# macOS / SwiftUI Development Guidelines

> Project-specific guidance for building TokChan as a simple macOS SwiftUI application.

## Project shape

This repository currently contains Trellis setup only; the app source has not been created yet. Until real source exists, these guidelines define the baseline conventions for the first SwiftUI implementation. After the initial app skeleton lands, update these files with concrete file paths and examples from the codebase.

## Guidelines Index

| Guide | Description | Status |
|-------|-------------|--------|
| [Directory Structure](./directory-structure.md) | Xcode project layout, app entry, feature folders, shared code | Baseline |
| [SwiftUI Guidelines](./swiftui-guidelines.md) | View composition, reusable components, previews, navigation | Baseline |
| [State Management](./state-management.md) | Local view state, observable models, environment, app services | Baseline |
| [Data Persistence](./data-persistence.md) | UserDefaults, local files, SwiftData/Core Data decision points | Baseline |
| [Networking Guidelines](./networking-guidelines.md) | API clients, async/await, decoding, offline boundaries | Baseline |
| [Quality Guidelines](./quality-guidelines.md) | Swift style, concurrency safety, accessibility, error handling | Baseline |
| [Testing Guidelines](./testing-guidelines.md) | Unit, view-model, and UI test expectations | Baseline |

## Default technology choices

- Language: Swift.
- UI framework: SwiftUI.
- Minimum app architecture: SwiftUI `App` entry point plus feature folders for a macOS target.
- Concurrency: Swift structured concurrency with `async` / `await`.
- State: prefer small `@State` and `@Observable` / `ObservableObject` models before adding a global store.
- External dependencies: avoid dependencies until a concrete need exists.

## Documentation language

Spec documents are written in English so future coding agents can load them consistently.
