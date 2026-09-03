# Networking Guidelines

## Current assumption

A backend is not part of this repository. If the app later calls a remote API, treat it as an external integration from the macOS app, not as an in-repo backend layer.

## Rules

- Use Swift structured concurrency with `async` / `await` for network calls.
- Keep API calls in service types, not in SwiftUI views.
- Define request and response models explicitly.
- Decode JSON with `Codable` unless an API shape requires custom parsing.
- Convert transport errors into user-meaningful states at the view-model boundary.
- Keep base URLs and feature flags in configuration, not hard-coded throughout the app.

## Testing

- Inject an `URLSession`-like client or service protocol for tests when network behavior matters.
- Unit tests should cover decoding of important response models and error mapping.

## Avoid

- Do not block the main thread for network work.
- Do not force unwrap decoded fields from remote payloads.
- Do not add backend scaffolding to this repo unless the product scope changes.
