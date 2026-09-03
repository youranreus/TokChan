# Technical Design

## Architecture

Keep the existing `TokChan/Features/Settings/SettingsView.swift` as the single feature entry point. The existing SwiftUI `Settings` scene remains the owner of the preferences window and its native titlebar chrome.

Use a private `SettingsTab: Hashable` enum with `general`, `autosubmit`, and `about` cases. A `@State` selection initialized to `.general` drives a root `TabView(selection:)`. Each page declares an SF Symbol and label through `.tabItem`, allowing macOS to promote the items into its native Preferences Toolbar and own selection, hover, material, spacing, separators, and dark-mode behavior.

## Layout and data flow

The root view is a native `TabView` with this stable item order:

1. 常规 (`slider.horizontal.3`)
2. 自动提交 (`arrow.clockwise.circle`)
3. 关于 (`info.circle`)

Each tab wraps its content with the existing status and save footer. All bindings remain attached to the same parent-owned local draft states, so switching tabs does not reset edits. The save action continues to construct `enteredPreferences` and `enteredAutosubmit`, then calls `viewModel.saveSettings` in a task and dismisses only after success.

The about content uses `Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String`, with `"未知"` as fallback. It displays the app name, version, and a short Tokscale companion description without adding mutable state or network work.

## Window behavior

Keep `dismiss` only where it is needed to close after a successful save. Do not render custom close, cancel, titlebar, or tab controls; the macOS Settings window's standard traffic lights handle window closing and the native toolbar handles navigation.

On macOS 14 and newer, open the Settings scene through `@Environment(\.openSettings)` in an availability-isolated helper view, activating the app immediately before the action. On macOS 13, use responder-chain `showSettingsWindow:` with `showPreferencesWindow:` as a compatibility fallback.

## Compatibility and rollback

The settings content uses APIs available on the project's macOS 13 deployment target. The macOS 14-only `openSettings` environment property is isolated in a view annotated with `@available(macOS 14.0, *)`, preserving macOS 13 compilation. No persistence migration or project-file change is required.

## Risks

- Native Preferences Toolbar layout can differ slightly across macOS releases; rely on the system rendering rather than adding version-specific visual simulation.
- Removing Cancel changes only the visible action surface; closing the window intentionally abandons local draft state because drafts are not written until Save.
