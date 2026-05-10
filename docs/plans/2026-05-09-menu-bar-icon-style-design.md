# Menu Bar Icon Style Design

## Context

Issue #11 reports that the menu bar icon remains white when the macOS menu bar background is light, making it hard to see. The current app creates an `NSStatusItem` in `Snap_TranslateApp.swift` and sets `StatusBarIcon` with `image.isTemplate = false`, so AppKit does not automatically adapt the icon color.

## Design

Add a user-facing menu bar icon style preference with three modes:

- Auto: use a template status item image so macOS renders the icon appropriately for the current menu bar appearance.
- Black: render the existing status bar icon mask as fixed black.
- White: render the existing status bar icon mask as fixed white.

Auto is the default because it fixes the reported light menu bar visibility issue while preserving native macOS behavior for dark menu bars.

## Components

- `MenuBarIconStyle` in `AppSettings.swift` models the three choices and display names.
- `SettingsStore` persists the choice in `UserDefaults`.
- `AppDelegate` listens for style changes and refreshes the `NSStatusBarButton` image without recreating the menu.
- `SystemSettingsView` adds a compact picker under the existing Show Menu Bar Icon toggle.

## Testing

Add settings tests for default style and persisted style loading. Run the app test suite and a Debug build.
