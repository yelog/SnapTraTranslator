# Manual OCR Region Selection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a manual OCR region selection correction path without changing the existing double-tap sentence translation behavior.

**Architecture:** Keep double-tap sentence translation as the primary path. Add a lightweight full-screen selection window that is opened from the paragraph translation panel, then route the selected screen rect into the existing manual paragraph OCR lookup flow.

**Tech Stack:** Swift, SwiftUI, AppKit `NSPanel`, ScreenCaptureKit via existing `ScreenCaptureService`.

---

### Task 1: Add Manual Selection Overlay

**Files:**
- Modify: `SnapTra Translator/OverlayWindowController.swift`

**Steps:**
1. Add a SwiftUI selection view with dimmed background, drag rectangle, and hint text.
2. Add an `NSViewRepresentable` mouse interaction layer to track drag start/update/end and Escape.
3. Add `ManualRegionSelectionWindowController` that shows one borderless panel per active screen and returns the selected `CGRect`.
4. Register the selection panels with `CaptureExclusionRegistry` so selected captures do not include SnapTra overlays.

### Task 2: Wire AppModel

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`

**Steps:**
1. Add a `manualRegionSelectionWindowController` property.
2. Expose `beginManualParagraphRegionSelection()` for the paragraph overlay button.
3. Hide transient highlight/debug overlays while selecting.
4. On selection completion, call the existing manual paragraph region lookup path.
5. On cancel, restore the previous paragraph overlay state without clearing results.

### Task 3: Add Paragraph Panel Action

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift`

**Steps:**
1. Add a compact `selection` or `crop` control button before pin/close in paragraph top bars.
2. Use localized help text `重新框选` / `Reselect Region` through existing `L()` fallback behavior.
3. Keep the control visible only for paragraph overlay modes.

### Task 4: Verify

**Commands:**
- Run: `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`
- Run relevant tests if build succeeds: `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test`

**Manual QA:**
1. Double-tap shortcut still translates the sentence under cursor.
2. Fast double-tap still keeps the sentence panel visible.
3. The paragraph panel `重新框选` button opens the selection overlay.
4. Dragging a region translates the selected text.
5. Escape cancels selection and keeps the previous result.
