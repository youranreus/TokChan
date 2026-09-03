# SwiftUI Guidelines

## View structure

- Use SwiftUI with value-type `View` structs.
- Keep `body` focused on layout and composition.
- Extract private computed subviews only when it improves readability or removes meaningful duplication.
- Prefer small feature views over a generic component library at project start.
- Use `private` helpers and subviews by default.

## State in views

- Use `@State` for simple view-owned UI state.
- Use `@Binding` when a child edits state owned by its parent.
- Use observable view models for async loading, persistence coordination, or multi-step business logic.
- Keep side effects in `.task`, button actions, or view models; do not trigger side effects while computing `body`.

## macOS UI patterns

- Prefer native macOS controls and window behavior over iOS-style interaction patterns.
- Use `NavigationSplitView` when the app has sidebar/detail structure; use `NavigationStack` only for clearly hierarchical flows.
- Keep navigation state explicit when screens need deep linking or restoration.
- Avoid stringly typed route identifiers; prefer enums or typed values once routing grows.

## Previews

- Add SwiftUI previews for non-trivial screens and reusable components.
- Previews should use lightweight sample data and must not perform live networking.

## Accessibility

- Provide accessible labels for icon-only buttons and custom controls.
- Respect system font sizing, dark mode, keyboard navigation, and pointer-focused interaction.
- Use system colors where possible so dark mode and contrast settings work by default.
