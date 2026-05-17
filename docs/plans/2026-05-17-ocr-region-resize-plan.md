# OCR Region Resize Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to drag the green OCR sentence region corners, then re-run OCR and translation for the adjusted rectangle when the drag ends.

**Architecture:** Keep the current automatic paragraph selection as the first step, then add a manual-region path after resize. `ParagraphHighlightWindowController` reports the adjusted screen rect to `AppModel`, `ScreenCaptureService` captures that rect, `OCRService` combines recognized lines, and existing paragraph translation state updates render the result.

**Tech Stack:** SwiftUI, AppKit, ScreenCaptureKit, Vision OCR, xcodebuild

---

### Task 1: Add rectangle capture support

**Files:**
- Modify: `SnapTra Translator/ScreenCaptureService.swift`

**Steps:**
- Add `capture(rect:) async -> (image: CGImage, region: CaptureRegion)?`.
- Resolve the screen from the rectangle midpoint.
- Intersect the requested rect with the screen frame.
- Reuse `getDisplay(for:)`, `convertToDisplayLocalCoordinates`, and `makeConfiguration(for:scaleFactor:)`.
- Return `nil` if the clamped rect has no size.

### Task 2: Expose OCR text for manual regions

**Files:**
- Modify: `SnapTra Translator/OCRService.swift`

**Steps:**
- Add a nonisolated static helper that takes `[RecognizedTextLine]` and returns reading-order text.
- Sort top-to-bottom, then left-to-right for same-line ties.
- Join lines with newlines and trim whitespace.
- Keep existing paragraph grouping unchanged.

### Task 3: Make OCR highlight corners draggable

**Files:**
- Modify: `SnapTra Translator/OverlayWindowController.swift`

**Steps:**
- Add a `ParagraphHighlightResizeCorner` enum for four corners.
- Add drag state to `ParagraphHighlightView`.
- Draw invisible hit targets over the four green corners.
- Use `DragGesture` to update the window frame through a resize callback.
- Clamp width and height to a minimum size.
- Send a resize-completed callback on drag end.
- Set the highlight panel to accept mouse events.

### Task 4: Re-run OCR and translation after resize

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`

**Steps:**
- Wire `paragraphHighlightWindowController.onResizeCompleted` in `init`.
- Add `handleParagraphRegionResizeCompleted(_:)`.
- Start a new lookup ID and cancel existing lookup work.
- Update `activeParagraphRect`, `overlayPreferredWidth`, and paragraph overlay loading state.
- Capture the adjusted rect with `captureService.capture(rect:)`.
- OCR the captured image with `recognizeParagraphsWithRawLines`.
- Build text from all recognized lines using the new helper.
- Reuse language resolution, third-party translation, and native `loadSentenceTranslationState` for the extracted text.
- Keep the highlight visible on failure so the user can adjust again.

### Task 5: Verify build

**Files:**
- Modify: none

**Steps:**
- Run `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`.
- Expected: build succeeds.
- If build fails, make the smallest fix and rerun.
