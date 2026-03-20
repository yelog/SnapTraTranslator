# Windows V1 Shell Bootstrap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create the first native Windows shell as a packaged WinUI 3 app that installs through MSIX, runs in the tray, registers a global hotkey, and opens a minimal settings window.

**Architecture:** Keep Windows work isolated under `apps/windows` and use a single-project packaged `C# + WinUI 3` app. Own tray and hotkey behavior through a hidden native message window plus thin Win32 interop services, while keeping OCR, capture, dictionary, translation, and speech as placeholder interfaces for later milestones.

**Tech Stack:** C#, WinUI 3, Windows App SDK, single-project MSIX, Win32 interop, JSON settings persistence

---

> **Prerequisite:** Execute this plan on a Windows 11 machine with Visual Studio 2022, the WinUI 3 / Windows App SDK workload, and MSIX packaging support installed. This repository cannot validate the Windows build from the current macOS environment.

### Task 1: Scaffold the packaged WinUI 3 project

**Files:**
- Create: `apps/windows/SnapTra.Windows.sln`
- Create: `apps/windows/src/SnapTra.Windows/SnapTra.Windows.csproj`
- Create: `apps/windows/src/SnapTra.Windows/App.xaml`
- Create: `apps/windows/src/SnapTra.Windows/App.xaml.cs`
- Create: `apps/windows/src/SnapTra.Windows/Package.appxmanifest`
- Create: `apps/windows/src/SnapTra.Windows/MainWindow.xaml`
- Create: `apps/windows/src/SnapTra.Windows/MainWindow.xaml.cs`

**Step 1: Create the Windows solution**

Use Visual Studio's `Blank App, Packaged (WinUI 3 in Desktop)` template:

- Solution name: `SnapTra.Windows`
- Project name: `SnapTra.Windows`
- Location: `apps/windows/src`

Ensure the generated `.sln` sits at `apps/windows/SnapTra.Windows.sln`.

**Step 2: Keep the project single-executable**

Verify the project uses single-project MSIX and does not add a separate packaging project.

Expected:
- one `.csproj`
- one app executable
- one `Package.appxmanifest`

**Step 3: Build Debug**

Run on Windows:

```bash
msbuild apps/windows/src/SnapTra.Windows/SnapTra.Windows.csproj /restore /p:Configuration=Debug
```

Expected:
- build succeeds
- a packaged desktop app output is produced

**Step 4: Commit**

```bash
git add apps/windows/SnapTra.Windows.sln apps/windows/src/SnapTra.Windows
git commit -m "feat: scaffold packaged windows shell app"
```

### Task 2: Add shell bootstrap and hidden message window

**Files:**
- Modify: `apps/windows/src/SnapTra.Windows/App.xaml.cs`
- Create: `apps/windows/src/SnapTra.Windows/Shell/NativeMethods.cs`
- Create: `apps/windows/src/SnapTra.Windows/Shell/ShellMessageWindow.cs`
- Modify: `apps/windows/src/SnapTra.Windows/MainWindow.xaml`
- Modify: `apps/windows/src/SnapTra.Windows/MainWindow.xaml.cs`

**Step 1: Add Win32 interop definitions**

Create `NativeMethods.cs` with the minimal P/Invoke surface needed for:

- `CreateWindowEx`
- `DefWindowProc`
- `RegisterClassEx`
- `DestroyWindow`
- `PostQuitMessage`
- window-style and message constants

Keep this file limited to shell bootstrap primitives in this task.

**Step 2: Add a hidden shell message window**

Create `ShellMessageWindow.cs` that:

- registers a window class
- creates a hidden window
- exposes its `HWND`
- forwards messages to a managed callback
- disposes the window cleanly

**Step 3: Start the app tray-first**

Update `App.xaml.cs` so startup:

- creates the hidden shell window
- does not immediately show the user-facing settings window

Keep `MainWindow` as a simple visible window that can be shown later by shell commands.

**Step 4: Build Debug**

Run:

```bash
msbuild apps/windows/src/SnapTra.Windows/SnapTra.Windows.csproj /restore /p:Configuration=Debug
```

Expected:
- build succeeds
- app launches without showing the settings window immediately

**Step 5: Commit**

```bash
git add apps/windows/src/SnapTra.Windows/App.xaml.cs \
        apps/windows/src/SnapTra.Windows/Shell/NativeMethods.cs \
        apps/windows/src/SnapTra.Windows/Shell/ShellMessageWindow.cs \
        apps/windows/src/SnapTra.Windows/MainWindow.xaml \
        apps/windows/src/SnapTra.Windows/MainWindow.xaml.cs
git commit -m "feat: add windows shell bootstrap window"
```

### Task 3: Add tray icon and native tray menu

**Files:**
- Create: `apps/windows/src/SnapTra.Windows/Shell/TrayIconService.cs`
- Modify: `apps/windows/src/SnapTra.Windows/Shell/NativeMethods.cs`
- Modify: `apps/windows/src/SnapTra.Windows/App.xaml.cs`

**Step 1: Extend interop for notification-area support**

Add the P/Invoke and constants needed for:

- `Shell_NotifyIcon`
- `NOTIFYICONDATA`
- `CreatePopupMenu`
- `AppendMenu`
- `TrackPopupMenu`
- tray callback message ids

**Step 2: Implement `TrayIconService`**

Create a tray service that:

- installs the notification icon
- removes it on shutdown
- shows a native popup menu
- emits commands for:
  - open settings
  - enable/disable hotkey
  - exit

**Step 3: Wire tray lifecycle into app bootstrap**

Update `App.xaml.cs` so the app:

- initializes the tray service after the hidden shell window exists
- routes tray commands to open settings or exit

**Step 4: Manual tray verification**

Run the app and confirm:

- the icon appears in the notification area
- the menu opens
- `Open Settings` shows the window
- `Exit` terminates the process and removes the icon

**Step 5: Commit**

```bash
git add apps/windows/src/SnapTra.Windows/Shell/TrayIconService.cs \
        apps/windows/src/SnapTra.Windows/Shell/NativeMethods.cs \
        apps/windows/src/SnapTra.Windows/App.xaml.cs
git commit -m "feat: add windows tray shell"
```

### Task 4: Add persisted settings and a minimal settings window

**Files:**
- Create: `apps/windows/src/SnapTra.Windows/Settings/SettingsModel.cs`
- Create: `apps/windows/src/SnapTra.Windows/Settings/SettingsStore.cs`
- Create: `apps/windows/src/SnapTra.Windows/Settings/SettingsViewModel.cs`
- Create: `apps/windows/src/SnapTra.Windows/Settings/SettingsWindow.xaml`
- Create: `apps/windows/src/SnapTra.Windows/Settings/SettingsWindow.xaml.cs`
- Modify: `apps/windows/src/SnapTra.Windows/App.xaml.cs`

**Step 1: Create the persisted settings model**

Define a simple JSON-backed model with:

- `SourceLanguage`
- `TargetLanguage`
- `HotkeyModifiers`
- `HotkeyKey`
- `IsHotkeyEnabled`
- `LaunchAtLoginRequested`

**Step 2: Add local settings storage**

Implement `SettingsStore.cs` to read and write:

```text
%LocalAppData%/SnapTraTranslator/settings.json
```

Use safe defaults if the file is missing or unreadable.

**Step 3: Add the settings window**

Create a minimal WinUI settings window with fields for:

- source language
- target language
- hotkey
- launch-at-login placeholder
- shell status placeholders

**Step 4: Bind the window through a view model**

Use `SettingsViewModel` to:

- load current settings
- save edits
- expose validation state for hotkey registration feedback later

**Step 5: Build and smoke test**

Run:

```bash
msbuild apps/windows/src/SnapTra.Windows/SnapTra.Windows.csproj /restore /p:Configuration=Debug
```

Expected:
- build succeeds
- settings values persist across relaunch

**Step 6: Commit**

```bash
git add apps/windows/src/SnapTra.Windows/Settings \
        apps/windows/src/SnapTra.Windows/App.xaml.cs
git commit -m "feat: add windows settings persistence"
```

### Task 5: Add global hotkey registration and re-registration

**Files:**
- Create: `apps/windows/src/SnapTra.Windows/Shell/GlobalHotkeyService.cs`
- Modify: `apps/windows/src/SnapTra.Windows/Shell/NativeMethods.cs`
- Modify: `apps/windows/src/SnapTra.Windows/App.xaml.cs`
- Modify: `apps/windows/src/SnapTra.Windows/Settings/SettingsViewModel.cs`

**Step 1: Extend interop for hotkeys**

Add the P/Invoke and constants needed for:

- `RegisterHotKey`
- `UnregisterHotKey`
- `WM_HOTKEY`
- hotkey modifier flags

**Step 2: Implement `GlobalHotkeyService`**

Create a service that:

- registers the active hotkey against the hidden shell window
- unregisters the previous hotkey on changes
- exposes success/failure state
- emits a managed event when `WM_HOTKEY` is received

**Step 3: Route hotkey messages**

Update shell message dispatch so `WM_HOTKEY` reaches `GlobalHotkeyService`.

For this milestone, the hotkey handler may:

- update internal state
- log a placeholder event
- expose a shell status message to settings

Do not start capture or OCR work yet.

**Step 4: Connect settings changes**

Update `SettingsViewModel` so changes to the hotkey:

- save to `SettingsStore`
- trigger re-registration
- surface failures to the UI

**Step 5: Manual verification**

Confirm:

- default hotkey registers on launch
- triggering the hotkey hits the placeholder handler
- changing the hotkey in settings re-registers it
- invalid or conflicting hotkeys surface a visible error state

**Step 6: Commit**

```bash
git add apps/windows/src/SnapTra.Windows/Shell/GlobalHotkeyService.cs \
        apps/windows/src/SnapTra.Windows/Shell/NativeMethods.cs \
        apps/windows/src/SnapTra.Windows/App.xaml.cs \
        apps/windows/src/SnapTra.Windows/Settings/SettingsViewModel.cs
git commit -m "feat: add windows global hotkey shell"
```

### Task 6: Add placeholder platform interfaces and package the app

**Files:**
- Create: `apps/windows/src/SnapTra.Windows/Platform/Capture/ICaptureService.cs`
- Create: `apps/windows/src/SnapTra.Windows/Platform/Ocr/IOcrService.cs`
- Create: `apps/windows/src/SnapTra.Windows/Platform/Dictionary/IDictionaryService.cs`
- Create: `apps/windows/src/SnapTra.Windows/Platform/Translation/ITranslationService.cs`
- Create: `apps/windows/src/SnapTra.Windows/Platform/Speech/ISpeechService.cs`
- Modify: `apps/windows/README.md`

**Step 1: Add placeholder platform contracts**

Create minimal interfaces for future work so the shell already has clean landing zones for:

- capture
- OCR
- dictionary
- translation
- speech

These can be empty or near-empty interfaces in this milestone, but their names should match the intended platform responsibilities.

**Step 2: Document the current Windows milestone**

Update `apps/windows/README.md` to say:

- the packaged WinUI 3 shell exists
- tray and hotkey bootstrap are present
- OCR, capture, dictionary, translation, and speech are not implemented yet

**Step 3: Build a Release MSIX package**

Run on Windows:

```bash
msbuild apps/windows/src/SnapTra.Windows/SnapTra.Windows.csproj /restore /p:Configuration=Release /p:GenerateAppxPackageOnBuild=true
```

Expected:
- build succeeds
- an installable MSIX package is produced

**Step 4: Install and smoke test**

Verify:

- the MSIX installs
- the app starts into the tray
- settings open
- hotkey still registers in the packaged build

**Step 5: Commit**

```bash
git add apps/windows/src/SnapTra.Windows/Platform \
        apps/windows/README.md
git commit -m "feat: package windows shell bootstrap"
```
