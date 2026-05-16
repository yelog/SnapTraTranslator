# Sentence Original Input Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the sentence translation source text editable in pinned mode so users can type or paste text and press `Return` to translate.

**Architecture:** Keep source text as part of `ParagraphOverlayContent`, add model methods for source mutation and explicit submit, and render the source region with either the existing read-only `SelectableTextView` or a new editable `NSTextView` wrapper based on `isParagraphOverlayPinned`.

**Tech Stack:** SwiftUI, AppKit, NSTextView, xcodebuild

---

### Task 1: Add model actions for edited source text

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`

**Steps:**
- Add `updateParagraphOriginalText(_:)` to update the current `ParagraphOverlayContent.originalText` without starting translation.
- Add `submitParagraphOriginalText()` to trim the current source text and re-run translation with the resolved language pair.
- Preserve existing `translateParagraphOriginal(to:)` behavior for language switching.

### Task 2: Render editable source input in pinned mode

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift`

**Steps:**
- Keep read-only source rendering for non-pinned overlays.
- Add editable source rendering for pinned overlays.
- Show placeholder text for empty pinned input.
- Show a compact submit hint only in pinned mode.

### Task 3: Add editable NSTextView wrapper

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift`

**Steps:**
- Add an `NSViewRepresentable` backed by `NSTextView`.
- Sync text changes back to SwiftUI/model.
- Intercept `insertNewline:` as submit.
- Allow `insertLineBreak:` for `Shift + Return`.
- Measure intrinsic height for overlay layout.

### Task 4: Verify

**Files:**
- Modify: none

**Steps:**
- Run `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`.
- Manually verify temporary read-only source, pinned editing, `Return` submit, and `Shift + Return` newline.
