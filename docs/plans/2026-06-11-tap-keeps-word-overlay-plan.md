# Tap Keeps Word Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional mode that keeps a word translation bubble visible after a short hotkey tap and dismisses it when the mouse moves away.

**Architecture:** Split the feature between gesture classification, persisted settings, and overlay lifecycle. Keep mouse-dismiss behavior in a small pure policy type so tests can cover threshold and protected-frame decisions without AppKit event synthesis.

**Tech Stack:** Swift, SwiftUI, AppKit `NSEvent`, XCTest, Xcode build system.

---

### Task 1: Gesture And Policy Tests

**Files:**
- Modify: `SnapTra TranslatorTests/HotkeyManagerTests.swift`
- Modify: `SnapTra TranslatorTests/ParagraphOverlayLayoutTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that expect a short tap release to be identifiable separately from a long hold and expect mouse movement outside the overlay to dismiss only after crossing the threshold.

- [ ] **Step 2: Run focused tests**

Run: `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/HotkeyManagerTests" -only-testing:"SnapTra TranslatorTests/ParagraphOverlayLayoutTests"`

Expected: FAIL because the new tap release kind and word overlay policy do not exist yet.

- [ ] **Step 3: Implement gesture and policy**

Add a tap-release callback in `HotkeyManager` and add `WordOverlayPersistencePolicy` near the other overlay policies in `AppModel.swift`.

- [ ] **Step 4: Re-run focused tests**

Expected: PASS for the new focused tests.

### Task 2: Settings Persistence

**Files:**
- Modify: `SnapTra Translator/AppSettings.swift`
- Modify: `SnapTra Translator/SettingsStore.swift`
- Modify: `SnapTra TranslatorTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing settings tests**

Assert the new setting defaults to `false`, persists to `UserDefaults`, and loads a stored `true` value.

- [ ] **Step 2: Run settings tests**

Run: `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/SettingsStoreMigrationTests"`

Expected: FAIL because the key and property do not exist yet.

- [ ] **Step 3: Implement persistence**

Add `AppSettingKey.keepWordOverlayAfterTap`, a `@Published` setting, initialization, and `persistAllSettings()` storage.

- [ ] **Step 4: Re-run settings tests**

Expected: PASS for settings tests.

### Task 3: AppModel And UI Integration

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`
- Modify: `SnapTra Translator/OverlayView.swift`
- Modify: `SnapTra Translator/SettingsView.swift`
- Modify: `SnapTra Translator/SettingsWindowView.swift`
- Modify: `SnapTra Translator/Localizable.xcstrings`
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `docs/README.md`

- [ ] **Step 1: Wire AppModel**

Use the tap-release callback to keep word overlays alive when enabled. Keep lookup tasks running so late translation and dictionary results can still update the bubble.

- [ ] **Step 2: Wire UI**

Show copy/close controls when either single-lookup mode is active or the tap-kept overlay is active. Add the new settings toggle near continuous translation.

- [ ] **Step 3: Update docs and localization**

Add user-facing strings and README text for the new mode.

- [ ] **Step 4: Verify**

Run focused tests, `jq empty "SnapTra Translator/Localizable.xcstrings"`, and a Debug build.
