# macOS Directory Structure

## Current state

No SwiftUI source exists yet. The first implementation should create a small, conventional macOS Xcode project rather than web-style `frontend` / `backend` folders.

## Recommended initial layout

Use one macOS app target directory named after the app, for example:

```text
TokChan/
  TokChanApp.swift
  Features/
    Home/
      HomeView.swift
      HomeViewModel.swift
  Shared/
    Components/
    Models/
    Services/
    Utilities/
  Resources/
    Assets.xcassets
    Localizable.xcstrings
  SupportingFiles/
    TokChan.entitlements
TokChanTests/
TokChanUITests/
TokChan.xcodeproj/
```

## Placement rules

- Put the SwiftUI `@main` app entry in `TokChanApp.swift` at the app target root.
- Put user-facing screens under `Features/<FeatureName>/`.
- Keep feature-specific view models beside the feature view.
- Put reusable visual pieces in `Shared/Components/` only after a second real use appears.
- Put domain models in `Shared/Models/` when shared by multiple features.
- Put integration boundaries such as persistence, networking, notification, or clock wrappers in `Shared/Services/`.
- Put tiny pure helpers in `Shared/Utilities/`; do not create a utility for one caller.
- Keep app resources in `Resources/` or the Xcode-generated asset/string catalogs.
- Keep macOS entitlements and app-sandbox capability files in `SupportingFiles/` or the Xcode project’s conventional location.

## Avoid

- Do not create `frontend/` or `backend/` directories for this project unless a real server or web client is introduced.
- Do not split every view into many files before the feature has real complexity.
- Do not place network or persistence calls directly inside SwiftUI view bodies.
