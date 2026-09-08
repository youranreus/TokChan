# macOS Quality Guidelines

## Swift style

- Prefer clear Swift names over abbreviations.
- Use `let` by default; use `var` only when mutation is required.
- Keep access control as narrow as practical.
- Prefer simple types and direct composition before introducing generic abstractions.
- Keep files focused on one primary type or feature concept.

## Error handling

- Use `do` / `catch` for recoverable failures.
- Show user-facing errors in plain language.
- Preserve technical error details in logs or debug descriptions where helpful.
- Avoid `try!`, `as!`, and force unwraps except in tests or truly impossible states with a nearby explanation.

## Concurrency

- Mark UI-facing view models `@MainActor` when they mutate displayed state.
- Cancel or ignore stale async work when views disappear or inputs change.
- Avoid detached tasks unless isolation and lifetime are explicitly understood.

## Accessibility and localization

- Design strings so they can move into `Localizable.xcstrings` when localization begins.
- Add accessibility labels and hints for custom controls.
- Test important screens with dynamic type in mind.

## Dependencies

- Avoid third-party packages until the standard library, SwiftUI, Foundation, and Apple frameworks are insufficient.
- Sparkle `2.7.1` is the reviewed exception for secure app replacement; keep its import and controller API behind `Shared/Services/AppUpdater.swift`, link it only to the app target, and keep `Package.resolved` committed. Do not spread Sparkle types into feature views or tests.
- A Sparkle version change requires review of minimum macOS support, release notes/license, embedded signable-code inventory, signing/notarization behavior, packaged command-line tool paths, feed compatibility, and a two-version update rehearsal. Update `release-workflow.md` and the recorded pin together.
- When adding any other dependency, document why it is needed, pin it reproducibly, and state what boundary contains it.
