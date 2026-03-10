# Layered Permission Readiness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the app show layered readiness for OCR word translation and selected-text sentence translation, so users can tell whether permissions are partially or fully complete.

**Architecture:** Derive capability-level readiness from `PermissionStatus` in `PermissionManager`, then bind both settings surfaces to those derived states instead of duplicating permission rules in the views. Keep the change focused on status modeling and settings presentation; do not change lookup execution in this plan.

**Tech Stack:** Swift, SwiftUI, XCTest, macOS Accessibility APIs, ScreenCaptureKit

---

### Task 1: Add Derived Capability State In PermissionManager

**Files:**
- Modify: `SnapTra Translator/PermissionManager.swift`
- Test: `SnapTra TranslatorTests/PermissionManagerTests.swift`

**Step 1: Write the failing test**

Create a new test file that covers the four readiness combinations:

```swift
func testCapabilityStateWhenNoPermissionsAreGranted() {
    let status = PermissionStatus(screenRecording: false, accessibility: false)
    XCTAssertFalse(status.canLookupWordByOCR)
    XCTAssertFalse(status.canTranslateSentenceSelection)
    XCTAssertFalse(status.isFullyReady)
    XCTAssertEqual(status.capabilitySummary, "未启用翻译能力")
}

func testCapabilityStateWhenOnlyScreenRecordingIsGranted() {
    let status = PermissionStatus(screenRecording: true, accessibility: false)
    XCTAssertTrue(status.canLookupWordByOCR)
    XCTAssertFalse(status.canTranslateSentenceSelection)
    XCTAssertEqual(status.capabilitySummary, "已启用单词翻译，句子翻译未启用")
}

func testCapabilityStateWhenOnlyAccessibilityIsGranted() {
    let status = PermissionStatus(screenRecording: false, accessibility: true)
    XCTAssertFalse(status.canLookupWordByOCR)
    XCTAssertTrue(status.canTranslateSentenceSelection)
    XCTAssertEqual(status.capabilitySummary, "已启用句子翻译，单词翻译未启用")
}

func testCapabilityStateWhenBothPermissionsAreGranted() {
    let status = PermissionStatus(screenRecording: true, accessibility: true)
    XCTAssertTrue(status.isFullyReady)
    XCTAssertEqual(status.capabilitySummary, "完整翻译能力已启用")
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/PermissionManagerTests"
```

Expected: FAIL because the computed properties do not exist yet.

**Step 3: Write minimal implementation**

Add computed properties to `PermissionStatus`:

```swift
extension PermissionStatus {
    var canLookupWordByOCR: Bool { screenRecording }
    var canTranslateSentenceSelection: Bool { accessibility }
    var isFullyReady: Bool { screenRecording && accessibility }

    var capabilitySummary: String {
        switch (screenRecording, accessibility) {
        case (false, false):
            return "未启用翻译能力"
        case (true, false):
            return "已启用单词翻译，句子翻译未启用"
        case (false, true):
            return "已启用句子翻译，单词翻译未启用"
        case (true, true):
            return "完整翻译能力已启用"
        }
    }
}
```

If the repo prefers localization wrappers, route the strings through the existing localization helper instead of hardcoding them in the view.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild` command and confirm the new tests pass.

**Step 5: Commit**

```bash
git add "SnapTra Translator/PermissionManager.swift" "SnapTra TranslatorTests/PermissionManagerTests.swift"
git commit -m "feat(settings): add layered permission capability state"
```

### Task 2: Update Permissions Card In SettingsView

**Files:**
- Modify: `SnapTra Translator/SettingsView.swift`

**Step 1: Write the failing test**

If a lightweight view-model style test is practical, add one for the summary mapping. If not, skip direct SwiftUI rendering tests and rely on the tested `PermissionStatus` summary helpers from Task 1.

**Step 2: Run test to verify current behavior is insufficient**

Run the Task 1 tests or manual preview verification and confirm there is no layered readiness summary in the permissions card.

**Step 3: Write minimal implementation**

Add a compact summary block above the permission rows. The block should display:

- the overall summary from `model.permissions.status.capabilitySummary`
- a line for OCR word translation readiness
- a line for selected-text sentence translation readiness

Suggested structure:

```swift
VStack(alignment: .leading, spacing: 8) {
    Text(model.permissions.status.capabilitySummary)
        .font(.system(size: 13, weight: .semibold))

    readinessLine(
        title: "OCR 单词翻译",
        isReady: model.permissions.status.canLookupWordByOCR,
        detail: "需要屏幕录制权限"
    )

    readinessLine(
        title: "选中文本句子翻译",
        isReady: model.permissions.status.canTranslateSentenceSelection,
        detail: "需要辅助功能权限"
    )
}
```

Update each permission row subtitle/purpose text so the user sees what each permission is for.

**Step 4: Run targeted verification**

Build and open the settings window. Verify the permissions card now clearly distinguishes word translation and sentence translation readiness.

**Step 5: Commit**

```bash
git add "SnapTra Translator/SettingsView.swift"
git commit -m "feat(settings): show layered permission readiness summary"
```

### Task 3: Unify General Settings Readiness Logic

**Files:**
- Modify: `SnapTra Translator/SettingsWindowView.swift`

**Step 1: Write the failing test**

If there is existing test coverage for general readiness, update it to assert that full readiness now depends on both permissions. If there is no practical test seam, document the expected matrix in comments for manual verification and keep automated coverage in `PermissionManagerTests`.

**Step 2: Run the relevant test or inspect current behavior**

Confirm the current `allPermissionsGranted` logic still depends only on `screenRecording`.

**Step 3: Write minimal implementation**

Replace duplicated readiness conditions with the capability helpers from `PermissionStatus`.

Use separate derived values when needed:

```swift
private var wordTranslationReady: Bool {
    model.permissions.status.canLookupWordByOCR
}

private var sentenceTranslationReady: Bool {
    model.permissions.status.canTranslateSentenceSelection
}

private var allPermissionsGranted: Bool {
    model.permissions.status.isFullyReady
}
```

Only use `allPermissionsGranted` where the UI truly means "full capability is available".

**Step 4: Run targeted verification**

Open the General settings tab and verify its ready/not-ready state no longer conflicts with the permissions card.

**Step 5: Commit**

```bash
git add "SnapTra Translator/SettingsWindowView.swift"
git commit -m "fix(settings): align readiness checks with layered permissions"
```

### Task 4: Run Full Tests And Manual Permission Matrix Check

**Files:**
- Test: `SnapTra TranslatorTests/PermissionManagerTests.swift`
- Test: `SnapTra TranslatorTests/SettingsStoreTests.swift`
- Test: `SnapTra TranslatorTests/LookupDirectionTests.swift`

**Step 1: Run the full test suite**

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test
```

Expected: PASS with the new permission state tests and existing tests still green.

**Step 2: Manual verification**

Test these states in the running app:

1. no permissions granted
2. only screen recording granted
3. only accessibility granted
4. both granted

For each state verify:

- summary text is correct
- OCR readiness line is correct
- sentence readiness line is correct
- permission buttons still open the right System Settings pane

**Step 3: Commit**

```bash
git add -A
git commit -m "test(settings): verify layered permission readiness flow"
```
