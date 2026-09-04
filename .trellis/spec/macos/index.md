# macOS / SwiftUI Development Guidelines

> Project-specific guidance for building TokChan as a simple macOS SwiftUI application.

## Project shape

TokChan is a dependency-free macOS 13 SwiftUI menu-bar app. `TokChanApp.swift` creates a window-style `MenuBarExtra`; feature UI lives under `TokChan/Features`, and external Tokscale/API/preferences boundaries live under `TokChan/Shared`.

## Guidelines Index

| Guide | Description | Status |
|-------|-------------|--------|
| [Directory Structure](./directory-structure.md) | Xcode project layout, app entry, feature folders, shared code | Baseline |
| [SwiftUI Guidelines](./swiftui-guidelines.md) | View composition, reusable components, previews, navigation | Baseline |
| [State Management](./state-management.md) | Local view state, observable models, environment, app services | Baseline |
| [Data Persistence](./data-persistence.md) | Preferences and stale-while-refresh dashboard snapshot cache | Active |
| [Networking Guidelines](./networking-guidelines.md) | API clients, async/await, decoding, offline boundaries | Baseline |
| [Quality Guidelines](./quality-guidelines.md) | Swift style, concurrency safety, accessibility, error handling | Baseline |
| [Testing Guidelines](./testing-guidelines.md) | Unit, view-model, and UI test expectations | Baseline |
| [Tokscale Integration](./tokscale-integration.md) | Public profile API, versioned npx commands, autosubmit, GUI PATH behavior | Active |
| [Build and Release Workflow](./release-workflow.md) | Version, universal ZIP, Tag, GitHub Release, validation, and rollback contracts | Active |

## Default technology choices

- Language: Swift.
- UI framework: SwiftUI.
- Minimum app architecture: SwiftUI `App` entry point plus feature folders for a macOS target.
- Concurrency: Swift structured concurrency with `async` / `await`.
- State: prefer small `@State` and `@Observable` / `ObservableObject` models before adding a global store.
- External dependencies: avoid dependencies until a concrete need exists.

## Documentation language

Spec documents are written in English so future coding agents can load them consistently.
