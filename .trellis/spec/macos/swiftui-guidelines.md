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
### Native preferences toolbar

For multi-section app preferences, keep the SwiftUI `Settings` scene and make its root navigation a `TabView`. Declare each preference page with an SF Symbol `Label` in `.tabItem`; macOS promotes these items into the window's native preferences toolbar and owns selection, hover, spacing, titlebar material, separators, traffic lights, and dark mode.

```swift
Settings {
    TabView(selection: $selectedTab) {
        GeneralSettingsView()
            .tabItem { Label("常规", systemImage: "slider.horizontal.3") }
            .tag(SettingsTab.general)

        AboutSettingsView()
            .tabItem { Label("关于", systemImage: "info.circle") }
            .tag(SettingsTab.about)
    }
}
```

Do not simulate this navigation with an in-content `HStack`, buttons, segmented controls, rounded rectangles, or custom material. Use AppKit `NSToolbar` bridging only if the native SwiftUI `Settings` + `TabView` behavior cannot meet a concrete requirement.

### Opening the settings scene

Use SwiftUI's `@Environment(\.openSettings)` action on macOS 14 and newer. Because `openSettings` is unavailable on macOS 13, isolate the environment property inside a view annotated `@available(macOS 14.0, *)`; an availability check around a call is not enough if the property is stored on a view available to macOS 13.

For the macOS 13 fallback, activate the app and send `showSettingsWindow:` through the responder chain, then fall back to `showPreferencesWindow:` if it is not handled. Do not find or raise the settings window by matching its localized title.

Required checks:

- Build using the project's minimum macOS deployment target.
- Verify opening settings from the menu bar when the app is not active.
- Verify reopening an existing settings window brings it forward.
- Keep the `Settings` scene as the owner of native window chrome and traffic-light controls.
## Previews

- Add SwiftUI previews for non-trivial screens and reusable components.
- Previews should use lightweight sample data and must not perform live networking.

## Accessibility

- Provide accessible labels for icon-only buttons and custom controls.
- Respect system font sizing, dark mode, keyboard navigation, and pointer-focused interaction.
- Use system colors where possible so dark mode and contrast settings work by default.
