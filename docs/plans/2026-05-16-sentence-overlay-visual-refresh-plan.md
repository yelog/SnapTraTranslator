# Sentence Overlay Visual Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refresh the pinned sentence translation overlay so the editable source field and translation output look like a native, refined macOS floating panel.

**Architecture:** Keep the current `ParagraphOverlayContent` data flow and editing behavior. Limit changes to SwiftUI/AppKit presentation in `OverlayView.swift`, reusing the existing editable and selectable text wrappers while adjusting layout, spacing, colors, borders, and helper views.

**Tech Stack:** SwiftUI, AppKit, NSTextView, xcodebuild

---

### Task 1: Refine source editor presentation

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift`

**Steps:**
- Update `editableParagraphOriginalTextView(text:)` so the editor looks like an inset native editing surface instead of a large white input box.
- Use softer light/dark fill colors, a lighter stroke, a slightly larger corner radius, and balanced horizontal/vertical padding.
- Keep `EditableParagraphTextView` behavior unchanged.
- Keep the submit hint, but reduce its visual weight and align it with the source editor.

### Task 2: Simplify language selector hierarchy

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift`

**Steps:**
- Update `paragraphLanguageSelector(content:)` to remove the long horizontal divider lines around the language pill.
- Use a compact centered capsule with subtle background and stroke.
- Preserve existing target-language button behavior and accessibility label.

### Task 3: Improve section spacing and output priority

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift`

**Steps:**
- Adjust padding around the original text area, language selector, native translation result, and service result cards.
- Keep translated output visually stronger than source helper controls.
- Avoid changing model state or translation logic.

### Task 4: Verify build

**Files:**
- Modify: none

**Steps:**
- Run `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`.
- Expected: build succeeds.
- If build fails from style or type errors in `OverlayView.swift`, fix the minimal issue and rerun.
