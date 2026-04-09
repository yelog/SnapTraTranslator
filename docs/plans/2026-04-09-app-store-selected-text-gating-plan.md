# App Store Selected Text Gating Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Hide selected-text translation capability in the App Store channel and guarantee that single-press lookups stay on the OCR path there.

**Architecture:** Add a distribution-channel capability helper for selected-text translation, then reuse it in both settings rendering and lookup routing. Keep persisted settings intact so the Direct build preserves user preference while the App Store build ignores the feature.

**Tech Stack:** Swift, SwiftUI, AppKit, XCTest

---

### Task 1: Add channel capability helper

**Files:**
- Modify: `SnapTra Translator/UpdateChecker.swift`
- Test: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Step 1: Write the failing test**

Extend the lookup routing tests to cover the unsupported selected-text capability case:

```swift
func testUnsupportedSelectedTextCapabilityFallsBackToOcrWord() {
    let snapshot = SelectedTextSnapshot(
        text: "Hello world",
        selectedRange: NSRange(location: 0, length: 11),
        bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
        sourceAppIdentifier: "com.apple.TextEdit"
    )

    let intent = SinglePressLookupRouter.resolve(
        isSelectedTextTranslationSupported: false,
        isSelectedTextTranslationEnabled: true,
        hasAccessibilityPermission: true,
        selectionSnapshot: snapshot
    )

    XCTAssertEqual(intent, .ocrWord)
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/SelectedTextLookupRoutingTests"
```

Expected: FAIL because routing does not yet understand channel capability.

**Step 3: Write minimal implementation**

- add `supportsSelectedTextTranslation` to `DistributionChannel`
- thread a support flag into the lookup router

**Step 4: Run test to verify it passes**

Run the same `xcodebuild` command and confirm the lookup routing tests pass.

**Step 5: Commit**

```bash
git add "SnapTra Translator/UpdateChecker.swift" "SnapTra Translator/LookupIntent.swift" "SnapTra TranslatorTests/SettingsStoreTests.swift"
git commit -m "feat: add channel gating for selected text routing"
```

### Task 2: Gate selected-text lookup at runtime

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`

**Step 1: Write the failing test**

If there is no clean seam for `AppModel`, rely on the routing test from Task 1 and manual verification for runtime short-circuiting.

**Step 2: Inspect current behavior**

Confirm that `resolveSinglePressLookupIntent` still calls `SelectedTextService` before it knows whether the current channel supports selected-text translation.

**Step 3: Write minimal implementation**

- add a computed capability check in `AppModel`
- short-circuit `resolveSinglePressLookupIntent` to `.ocrWord` when selected-text translation is unsupported
- skip `SelectedTextService.currentSelectionSnapshot(...)` in that case

**Step 4: Run targeted verification**

Build the app and confirm the code compiles.

**Step 5: Commit**

```bash
git add "SnapTra Translator/AppModel.swift"
git commit -m "fix: skip selected text lookup in app store channel"
```

### Task 3: Hide unsupported settings in General

**Files:**
- Modify: `SnapTra Translator/SettingsWindowView.swift`

**Step 1: Write the failing test**

There is no practical SwiftUI test seam in the repo today, so use targeted build verification and manual inspection.

**Step 2: Inspect current behavior**

Confirm that the General tab always renders both the Accessibility permission row and the selected-text translation toggle.

**Step 3: Write minimal implementation**

- derive a shared `supportsSelectedTextTranslation` view state
- render the Accessibility permission row only when supported
- render the `Translate Selected Text` toggle only when supported
- remove selected-text capability from readiness calculation when unsupported
- keep the rest of the General tab unchanged

**Step 4: Run targeted verification**

Build the app and inspect the General tab in both distribution channels.

**Step 5: Commit**

```bash
git add "SnapTra Translator/SettingsWindowView.swift"
git commit -m "fix(settings): hide unsupported selected text controls in app store"
```

### Task 4: Verify end-to-end behavior

**Files:**
- Modify if needed: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Step 1: Run targeted tests**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/SelectedTextLookupRoutingTests"
```

Expected: PASS.

**Step 2: Run build verification**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Release -destination 'platform=macOS' build
```

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator Direct" -configuration Release -destination 'platform=macOS' build
```

Expected:

- both builds succeed
- App Store build hides selected-text controls
- Direct build still exposes them

**Step 3: Manual verification**

Check:

1. App Store channel General tab hides Accessibility and `Translate Selected Text`
2. App Store channel single-press lookup always behaves like OCR word lookup
3. Direct channel still shows Accessibility and `Translate Selected Text`
4. Direct channel selected-text translation still works when available

**Step 4: Commit**

```bash
git add -A
git commit -m "test: verify app store selected text gating"
```
