# macOS Directory Structure

## Current state

The repository contains one conventional Xcode project with three targets: `TokChan`, `TokChanTests`, and `TokChanUITests`.

## Recommended initial layout

Use one macOS app target directory named after the app, for example:

```text
TokChan/
  TokChanApp.swift
  Features/
    Dashboard/
      DashboardView.swift
      DashboardViewModel.swift
      DashboardView+Preview.swift
    Settings/
      SettingsView.swift
  Shared/
    Components/
    Models/
    Services/
    Utilities/
TokChanTests/
TokChanUITests/
TokChan.xcodeproj/
```

Resources and entitlements should only be added when the app gains assets, localization, or capabilities that require them. The current agent-style app uses generated Info.plist keys and intentionally has no App Sandbox entitlement because it must execute Tokscale and manage its LaunchAgent through the official CLI.

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

## Asset catalogs and branded images

Keep branded app resources in `TokChan/Assets.xcassets` and separate assets by rendering contract:

- `AppIcon.appiconset` owns the complete macOS 1x/2x icon matrix. Set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` in both Debug and Release app-target configurations; verify that the built app contains `AppIcon.icns` and that `CFBundleIconName` resolves to `AppIcon`.
- Menu-bar artwork must use its own image set with `template-rendering-intent` set to `template`. Supply 1x and 2x PNGs with transparent backgrounds and monochrome visible pixels so macOS can tint normal, dark, and selected states.
- Full-color transparent artwork belongs in a separate image set for in-app presentation such as the About page. Render it with `resizable()` and `scaledToFit()` plus a bounded frame to preserve aspect ratio.
- Do not reuse a full-color app icon directly as a menu-bar image; color-only detail and a filled square canvas do not survive template rendering at menu-bar size.

Required checks:

- Build the macOS 13 target and reject asset-catalog missing-slot, unreadable-resource, or unresolved-name warnings.
- Confirm every AppIcon output has the declared pixel dimensions and transparent corners.
- Confirm menu-bar outputs are monochrome, retain alpha-antialiased edges, and include visible padding at 18 × 18 and 36 × 36 pixels.

## Avoid

- Do not create `frontend/` or `backend/` directories for this project unless a real server or web client is introduced.
- Do not split every view into many files before the feature has real complexity.
- Do not place network or persistence calls directly inside SwiftUI view bodies.

## Client brand resources

ClientIcon maps canonical API IDs to bundled client-* image sets; codex maps to openai and kilo to kilocode. Unknown IDs use the generic terminal fallback. Keep original upstream files and commit provenance under Resources/ClientOriginals and include the upstream license. Asset catalogs use original rendering; the Zed WebP has a PNG presentation copy because actool requires a supported format. Add every upstream client image, not only clients currently present in an account.

TokenBreakdownTests must load all known image names from the app bundle. Network image loading is reserved for the user avatar, never client logos.
