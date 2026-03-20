# Windows V1 Shell Bootstrap Design

**Goal:** Add the first native Windows deliverable as a packaged app that installs via MSIX, runs as a tray-first utility, registers a global hotkey, and opens a lightweight settings window, without changing the existing macOS targets.

## Problem

- The repository now has the protocol and shared-domain seams needed for future platform shells, but Windows still has no executable shell, no build system, and no package output.
- The product depends on desktop-native behaviors such as tray presence, global hotkeys, window ownership, and packaging, all of which must be implemented with Windows-specific APIs.
- The first Windows milestone should be small enough to ship as a native shell bootstrap, but complete enough to prove installation, startup, tray lifecycle, and hotkey plumbing.
- The macOS App Store and direct-distribution targets must remain untouched while Windows work begins.

## Product Decisions

### Scope

- Build a native Windows shell under `apps/windows`.
- Use `C# + WinUI 3 + Win32 interop`.
- Use a single executable so the app can ship through single-project MSIX.
- Make the app tray-first: launch into the tray, not into a visible main window.
- Support a global hotkey registration path with a configurable placeholder hotkey.
- Provide a minimal settings window for:
  - source language
  - target language
  - hotkey
  - launch-at-login placeholder
  - shell diagnostics placeholders for OCR, translation, and dictionary
- Persist settings locally on Windows.
- Produce an installable MSIX package as the first deliverable.

### Non-Goals

- Do not implement OCR, screen capture, paragraph mode, overlay windows, or offline dictionary lookup in this milestone.
- Do not share Swift UI or Swift implementation code with Windows.
- Do not add a helper process, service, or second executable.
- Do not introduce Rust or C++ shared core code in this milestone.
- Do not modify the macOS Xcode target, entitlements, or build scripts.

## Constraints

### Packaging Constraint

- The first Windows app must stay as a single executable so it can use single-project MSIX.
- If the app later needs multiple executables, it should move to a Windows Application Packaging Project in a later phase.

### Repository Constraint

- All Windows source must stay under `apps/windows`.
- No Windows build files should be wired into the macOS Xcode project.

### Dependency Constraint

- Use Windows platform APIs for tray and hotkeys.
- Do not add third-party tray or hotkey wrappers in the bootstrap milestone.

## Recommended Architecture

### 1. Single-Project Packaged WinUI 3 App

Create a packaged WinUI 3 desktop app using the official single-project MSIX shape.

- `WinUI 3` provides the settings window and app lifecycle.
- MSIX packaging lives in the same project.
- The app stays small by avoiding an extra packaging project and by keeping a single executable.

### 2. Tray-First Shell With a Hidden Native Message Window

The Windows shell should not depend on the settings window for tray and hotkey lifetime.

- Create a hidden native message window at startup.
- Use this hidden window as the owner for:
  - `Shell_NotifyIcon` tray integration
  - `RegisterHotKey`
  - `WM_HOTKEY`
  - tray callback messages
- Create and show the WinUI settings window only on demand from the tray menu.

This avoids tying shell lifetime to a visible window and maps better to the current macOS menu-bar-style product behavior.

### 3. Thin Service Split Inside the Windows App

Use a small Windows-specific shell layer with separate responsibilities:

- `TrayIconService`
  - owns `NOTIFYICONDATA`
  - installs and removes the tray icon
  - shows the native popup menu
- `GlobalHotkeyService`
  - registers and unregisters the active hotkey
  - raises an in-process event when `WM_HOTKEY` arrives
- `ShellMessageWindow`
  - owns the hidden HWND
  - dispatches tray and hotkey messages
- `SettingsStore`
  - reads and writes persisted settings
- `SettingsWindow`
  - displays current settings and applies edits

Keep OCR, capture, dictionary, translation, and speech under placeholder platform interfaces so the shell can later connect to the same product semantics without another structural rewrite.

### 4. Single-Exe Bootstrap Flow

Boot sequence:

1. App launches.
2. Hidden shell message window is created.
3. Settings are loaded.
4. Tray icon is installed.
5. Global hotkey is registered.
6. No visible settings window is shown until the user asks for it.

Shutdown sequence:

1. User clicks `Exit` from the tray menu.
2. Hotkey is unregistered.
3. Tray icon is removed.
4. Settings window, if open, is closed.
5. Process exits cleanly.

## Repository Shape

```text
apps/windows/
├─ README.md
├─ SnapTra.Windows.sln
└─ src/
   └─ SnapTra.Windows/
      ├─ App.xaml
      ├─ App.xaml.cs
      ├─ Package.appxmanifest
      ├─ SnapTra.Windows.csproj
      ├─ Assets/
      ├─ Shell/
      │  ├─ NativeMethods.cs
      │  ├─ ShellMessageWindow.cs
      │  ├─ TrayIconService.cs
      │  └─ GlobalHotkeyService.cs
      ├─ Settings/
      │  ├─ SettingsStore.cs
      │  ├─ SettingsModel.cs
      │  ├─ SettingsViewModel.cs
      │  ├─ SettingsWindow.xaml
      │  └─ SettingsWindow.xaml.cs
      └─ Platform/
         ├─ Capture/ICaptureService.cs
         ├─ Ocr/IOcrService.cs
         ├─ Dictionary/IDictionaryService.cs
         ├─ Translation/ITranslationService.cs
         └─ Speech/ISpeechService.cs
```

## Key Flows

### Tray Flow

1. App starts and creates the hidden shell window.
2. `TrayIconService` adds the icon to the notification area.
3. Left click or double click opens settings.
4. Right click shows the native tray menu.
5. Menu commands:
   - Open Settings
   - Enable Hotkey / Disable Hotkey
   - Exit

### Hotkey Flow

1. `SettingsStore` loads the persisted hotkey.
2. `GlobalHotkeyService` calls `RegisterHotKey`.
3. Hidden shell window receives `WM_HOTKEY`.
4. The app updates internal shell state and emits a placeholder event for future capture/OCR flow.
5. The settings window can change and re-register the hotkey.

### Settings Flow

1. User opens settings from the tray menu.
2. `SettingsWindow` binds to `SettingsViewModel`.
3. `SettingsViewModel` reads current values from `SettingsStore`.
4. Changes are saved back to `SettingsStore`.
5. Hotkey changes trigger re-registration through `GlobalHotkeyService`.

## Data Model

Persist a single JSON settings record under `%LocalAppData%/SnapTraTranslator/settings.json`.

Recommended first fields:

- `sourceLanguage`
- `targetLanguage`
- `hotkeyModifiers`
- `hotkeyKey`
- `isHotkeyEnabled`
- `launchAtLoginRequested`

These fields should mirror current product intent, but they do not need to match the Swift persistence format byte-for-byte in this milestone.

## Error Handling

- If tray icon creation fails, exit early with a logged shell error because the app has no other primary entry point in this milestone.
- If hotkey registration fails, keep the app running, mark the hotkey as disabled, and surface the failure in settings.
- If settings persistence fails, preserve in-memory values for the current session and show an error state in settings.
- If the settings window cannot be created, keep tray and hotkey services alive and allow retry from the tray menu.

## Verification Strategy

### Build and Package

- Build Debug on Windows with Visual Studio 2022 and Windows App SDK support installed.
- Build Release with `GenerateAppxPackageOnBuild=true`.
- Confirm the generated MSIX installs and launches.

### Manual Shell Checks

- Launch the app and confirm it starts into the tray.
- Open settings from the tray.
- Exit from the tray and confirm cleanup.
- Register the default hotkey and verify the process receives it.
- Change the hotkey in settings and verify re-registration.
- Install the generated MSIX on a clean Windows machine if available.

## Recommended Milestones

### Milestone 1

- Scaffold packaged WinUI 3 project
- Produce Debug build
- Produce Release MSIX package

### Milestone 2

- Add hidden shell message window
- Add tray icon and tray menu
- Add exit and open-settings commands

### Milestone 3

- Add settings persistence
- Add global hotkey registration and re-registration
- Add placeholder platform interfaces for capture, OCR, dictionary, translation, and speech

## Sources

Validated against Microsoft Learn pages accessed on 2026-03-20:

- [Package your app using single-project MSIX](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/single-project-msix)
- [Windows App SDK deployment guide for framework-dependent packaged apps](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deploy-packaged-apps)
- [WinUI 3](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/)
- [Notification area](https://learn.microsoft.com/en-us/windows/win32/shell/notification-area)
- [RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey)
- [WM_HOTKEY](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-hotkey)
- [Get Started with Text Recognition (OCR) in the Windows App SDK](https://learn.microsoft.com/en-us/windows/ai/apis/text-recognition)
