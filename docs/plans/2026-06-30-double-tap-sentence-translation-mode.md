# Double Tap Sentence Translation Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let users choose whether double-tapping the hotkey automatically detects the paragraph under the cursor or starts manual region selection.

**Architecture:** Keep `ocrSentenceTranslationEnabled` as the master switch for double-tap sentence translation. Add a small persisted enum for the range source, and route `AppModel.handleHotkeyDoubleTap()` through a pure policy so UI state and window work stay out of the decision logic.

**Tech Stack:** Swift, SwiftUI, AppKit overlay controllers, XCTest, UserDefaults-backed settings.

---

### Task 1: Add Setting Model And Policy

**Files:**
- Modify: `SnapTra Translator/AppSettings.swift`
- Modify: `SnapTra Translator/SettingsStore.swift`
- Test: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Steps:**
1. Add failing tests for default mode, persisted mode, and double-tap policy.
2. Add `DoubleTapSentenceTranslationMode` with `.cursorParagraph` and `.manualRegion`.
3. Persist the selected mode using a new `AppSettingKey`.
4. Add `DoubleTapSentenceTranslationPolicy.resolve(...)` returning `.disabled`, `.automaticOCR`, or `.manualRegionSelection`.

### Task 2: Wire Double-Tap Runtime Behavior

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`

**Steps:**
1. Route `handleHotkeyDoubleTap()` through `DoubleTapSentenceTranslationPolicy`.
2. Keep current behavior for `.automaticOCR`.
3. Add a direct manual-selection path for `.manualRegionSelection` that does not require an existing paragraph overlay.
4. Preserve existing permission and debug overlay handling.

### Task 3: Update Settings UI And Localization

**Files:**
- Modify: `SnapTra Translator/SettingsWindowView.swift`
- Modify: `SnapTra Translator/Localizable.xcstrings`

**Steps:**
1. Rename the master toggle from “Double-tap OCR Sentence Translation” to “Double-tap Sentence Translation”.
2. Show a child picker only when the toggle is enabled.
3. Add localized strings for the new label and options.

### Task 4: Verify

**Commands:**
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test`
- If scheme test execution is unavailable, run the test target build and the app build, then report the limitation clearly.
