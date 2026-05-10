# Learning Export Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let users export learned words with explanations for Anki or spreadsheet review.

**Architecture:** Persist a compact definition snapshot on each lookup and keep export formatting in a dedicated service. The learning settings UI invokes the service and writes the selected format through a macOS save panel.

**Tech Stack:** SwiftUI, SwiftData, AppKit `NSSavePanel`, XCTest.

---

### Task 1: Persist Definition Snapshots

**Files:**
- Modify: `SnapTra Translator/WordRecord.swift`
- Modify: `SnapTra Translator/LearningService.swift`
- Modify: `SnapTra Translator/AppModel.swift`

**Steps:**
1. Add optional `definitionText` to `WordRecord`.
2. Add `recordLookup(word:definitionText:)` to update lookup metadata and optionally refresh the stored definition.
3. Add `updateDefinition(word:definitionText:)` for asynchronous dictionary/translation results.
4. Build a compact explanation from `OverlayContent` using ready primary translation and dictionary definition summaries.
5. Call `updateDefinition` after primary translation and dictionary section updates.

### Task 2: Add Export Service

**Files:**
- Create: `SnapTra Translator/LearningExportService.swift`
- Modify: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Steps:**
1. Add `LearningExportFormat` with `.ankiTSV` and `.csv`.
2. Add `LearningExportRow` for testable export input.
3. Implement TSV and CSV escaping.
4. Add tests for header, row content, and escaping.

### Task 3: Add Learning Page Export UI

**Files:**
- Modify: `SnapTra Translator/LearningSettingsView.swift`

**Steps:**
1. Add export status state.
2. Add buttons for Anki TSV and CSV near search/filter controls.
3. Present `NSSavePanel`, generate content from filtered rows, and write UTF-8 data.
4. Show success/failure feedback.

### Task 4: Verify

**Commands:**
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test`

**Expected:**
Build succeeds. Tests pass or report only environment/signing constraints unrelated to the implementation.
