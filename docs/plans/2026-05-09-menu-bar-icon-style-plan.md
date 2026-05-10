# Menu Bar Icon Style Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Auto, Black, and White menu bar icon style choices so the status bar icon remains visible on light and dark menu bars.

**Architecture:** Persist a new `MenuBarIconStyle` setting in `SettingsStore`. `AppDelegate` derives the current `NSStatusBarButton.image` from the setting, using template rendering for Auto and alpha-mask tinting for fixed Black/White. `SystemSettingsView` exposes the setting next to existing system appearance controls.

**Tech Stack:** Swift, SwiftUI, AppKit `NSStatusItem`, XCTest, UserDefaults.

---

### Task 1: Add Setting Model

**Files:**
- Modify: `SnapTra Translator/AppSettings.swift`
- Modify: `SnapTra Translator/SettingsStore.swift`
- Test: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Steps:**
- Add `MenuBarIconStyle: String, CaseIterable, Identifiable` with `auto`, `black`, and `white`.
- Add `AppSettingKey.menuBarIconStyle`.
- Add `SettingsStore.menuBarIconStyle`, defaulting to `.auto`.
- Persist it in `didSet` and `persistAllSettings()`.
- Add tests for default and persisted loading.

### Task 2: Render Status Item Image From Setting

**Files:**
- Modify: `SnapTra Translator/Snap_TranslateApp.swift`

**Steps:**
- Subscribe to `$menuBarIconStyle` changes in `applicationDidFinishLaunching`.
- Add `updateStatusItemImage()`.
- Update `makeStatusBarImage()` to set `isTemplate = true` for Auto.
- For Black/White, tint the source icon via its alpha mask and set `isTemplate = false`.

### Task 3: Add Settings UI

**Files:**
- Modify: `SnapTra Translator/SettingsWindowView.swift`

**Steps:**
- Add a `MenuBarIconStylePickerRow` with a menu picker.
- Insert it below Show Menu Bar Icon in `SystemSettingsView`.

### Task 4: Verify

**Commands:**
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test`
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

**Expected:** Tests and Debug build pass.
