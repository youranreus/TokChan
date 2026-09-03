# State Management

## Default approach

Keep state as local as possible. This is planned as a simple SwiftUI app, so global stores are not the default.

## Rules

- Use `@State` for simple screen-local values.
- Use `@Binding` for parent-child edit flows.
- Use `@Environment` for system values and app-wide dependencies that SwiftUI already models well.
- Use `@Observable` on modern OS targets, or `ObservableObject` / `@StateObject` / `@ObservedObject` when compatibility requires it.
- Keep view models on the main actor when they publish UI state.
- Model loading states explicitly, for example idle / loading / loaded / failed, instead of relying on optional data alone.

## Service boundaries

- Inject persistence, networking, clock, and UUID generation into view models when behavior needs tests.
- Prefer protocols only at real boundaries; do not protocol-wrap every concrete type prematurely.

## Avoid

- Do not introduce Redux-style global state without a concrete multi-feature need.
- Do not store derived display strings as independent mutable state when they can be computed from source data.
- Do not mutate UI state from background tasks outside the main actor.
