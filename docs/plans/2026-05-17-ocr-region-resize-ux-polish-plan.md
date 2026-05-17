# OCR Region Resize UX Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Polish OCR region resizing by using proper diagonal cursors and hiding the translation panel during corner drag.

**Architecture:** Keep resize geometry and OCR retranslation unchanged. Add a resize-began callback from `ParagraphHighlightWindowController` to `AppModel`, let `AppModel` temporarily hide only the translation panel window, and use AppKit diagonal resize cursors for the corner handles.

**Tech Stack:** SwiftUI, AppKit, xcodebuild

---

### Task 1: Add resize begin callback

**Files:**
- Modify: `SnapTra Translator/OverlayWindowController.swift`
- Modify: `SnapTra Translator/AppModel.swift`

**Steps:**
- Add `onResizeBegan: (() -> Void)?` to `ParagraphHighlightWindowController`.
- Call it once when a resize drag starts, using `resizeStartFrame == nil` as the guard.
- Wire the callback in `AppModel.init` to a new `handleParagraphRegionResizeBegan()` method.

### Task 2: Hide translation panel during drag

**Files:**
- Modify: `SnapTra Translator/OverlayWindowController.swift`
- Modify: `SnapTra Translator/AppModel.swift`

**Steps:**
- Add a lightweight method on `OverlayWindowController` to hide the window without mutating `AppModel.overlayState`.
- In `handleParagraphRegionResizeBegan()`, call that method.
- Do not call `hideOverlay()` because it also hides the green OCR region and clears paragraph state.
- Keep existing resize-end logic unchanged so `updateOverlay(.paragraphLoading)` shows the panel again after release.

### Task 3: Use diagonal resize cursors

**Files:**
- Modify: `SnapTra Translator/OverlayWindowController.swift`

**Steps:**
- Replace horizontal/vertical cursor mapping with diagonal resize cursors.
- Top-left and bottom-right use northwest-southeast direction.
- Top-right and bottom-left use northeast-southwest direction.
- Ensure cursor remains set while dragging.

### Task 4: Verify build

**Files:**
- Modify: none

**Steps:**
- Run `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`.
- Expected: build succeeds.
- If build fails, make the smallest fix and rerun.
