# Learning TXT Export Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let users export looked-up learning words as a simple TXT word list.

**Architecture:** Reuse the existing learning export flow. Add TXT as a `LearningExportFormat`, generate one word per line in `LearningExportService`, and expose the format as the first export action in `LearningSettingsView`.

**Tech Stack:** Swift, SwiftUI, AppKit `NSSavePanel`, SwiftData, XCTest.

---

### Task 1: Add TXT Export Formatting

**Files:**
- Modify: `SnapTra Translator/LearningExportService.swift`
- Test: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Step 1: Write the failing test**

Add a test to `LearningExportServiceTests`:

```swift
func testPlainTextExportWritesOneWordPerLine() {
    let rows = [
        LearningExportRow(word: "apple", sourceLanguageName: "English", definitionText: "n. apple", lookupCount: 3, reviewStage: 1, isMastered: false),
        LearningExportRow(word: "banana", sourceLanguageName: "English", definitionText: "n. banana", lookupCount: 1, reviewStage: 0, isMastered: false),
    ]

    let output = LearningExportService.export(rows: rows, format: .plainText)

    XCTAssertEqual(output, "apple\nbanana\n")
}
```

**Step 2: Run focused test to verify failure**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test -only-testing:SnapTra_TranslatorTests/LearningExportServiceTests
```

Expected: fails because `.plainText` does not exist yet.

**Step 3: Implement TXT**

Add `.plainText` to `LearningExportFormat`, return display name `TXT`, file extension `txt`, and format rows as `rows.map(\.word).joined(separator: "\n") + "\n"`.

**Step 4: Run focused test**

Run the same command. Expected: pass.

### Task 2: Add TXT UI Entry

**Files:**
- Modify: `SnapTra Translator/LearningSettingsView.swift`
- Modify: `SnapTra Translator/Localizable.xcstrings`

**Step 1: Add the TXT button**

Place a small `TXT` export button before Anki and CSV in the existing export row. Use a document-style SF Symbol and call `exportWords(format: .plainText)`.

**Step 2: Update help copy**

Change help text from "current words" to "matching words" for TXT, Anki, and CSV.

**Step 3: Add localized strings**

Add localization entries for the new help text. Existing labels that are file format names can remain short and language-neutral.

### Task 3: Verify

**Commands:**

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test -only-testing:SnapTra_TranslatorTests/LearningExportServiceTests
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

**Expected:** Focused tests pass and the Debug build succeeds.
