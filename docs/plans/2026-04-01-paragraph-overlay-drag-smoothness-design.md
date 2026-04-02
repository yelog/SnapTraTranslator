# Paragraph Overlay Drag Smoothness Design

Date: 2026-04-01

## Goal

Fix paragraph-overlay dragging so a pinned sentence panel can always be moved by dragging the original-text lines, and make the movement feel direct and smooth regardless of whether the panel came from OCR double-tap or selected-text sentence lookup.

## Problem Analysis

The current issues come from three separate layers competing with each other:

1. **Release-state drift in `AppModel`**
   - The app can keep a visible paragraph overlay while still resetting lookup mode back to `.word`.
   - That makes the persistent paragraph session weaker than it should be and can leave interaction state inconsistent.

2. **Manual drag loses to automatic paragraph alignment**
   - Paragraph overlays with `activeParagraphRect` are repeatedly re-aligned through `alignToSentenceRect(...)` as content updates arrive.
   - If the user has already started moving the panel manually, those refreshes still try to move the window back to the detected paragraph position.
   - Result: visible stutter, snap-back, and ghosted movement during drag.

3. **Original text body has no dedicated drag capture path**
   - The body uses `SelectableTextView`, backed by `NSTextView`.
   - Header dragging exists, but the original-text lines do not have a reliable drag capture layer.
   - Result: dragging from the body can fall back to text selection instead of moving the panel.

## Product Decisions

### Drag Availability

- A paragraph overlay becomes draggable from the original-text body once it is in the pinned/persistent state.
- This applies to both:
  - OCR sentence overlay from hotkey double-tap
  - selected-text sentence overlay from single-press routing

### Manual Position Priority

- Once the user begins manual positioning, layout refreshes must preserve the manual origin.
- While the drag is actively in progress, content-driven layout refreshes should not re-anchor the panel.
- After drag ends, the panel may refresh its size, but it must stay at the user-selected origin.

### Interaction Tradeoff

- In pinned state, the original-text body prioritizes drag over text selection.
- This is intentional because the user explicitly wants to drag the panel from the original lines.
- Translation text keeps its existing selectable behavior.

## Recommended Approach

### 1. Keep paragraph session state coherent in `AppModel`

- If a paragraph overlay remains visible after release, keep the paragraph session active instead of resetting to `.word` immediately.
- Preserve `Esc` monitoring and interactive window state while the pinned paragraph overlay is on screen.

### 2. Make manual positioning stronger than sentence re-alignment

- Expose whether `OverlayWindowController` is currently being manually dragged or already has a manual origin.
- When either condition is true:
  - skip active drag-time re-layout churn
  - preserve manual origin on later content refreshes
  - avoid re-running paragraph placement animation

### 3. Add a drag capture layer over the original-text section

- Add a clear overlay on top of the original-text body only when the paragraph overlay is pinned.
- Route that drag layer through the existing drag helpers in `AppModel`.
- Keep the current top-bar drag path as an additional drag handle.

## Files

- `SnapTra Translator/AppModel.swift`
- `SnapTra Translator/OverlayWindowController.swift`
- `SnapTra Translator/OverlayView.swift`

## Validation

- OCR double-tap, persistent paragraph panel:
  - drag from original-text lines moves the whole panel
  - no snap-back while translations continue to fill in
- selected-text sentence panel:
  - click pin
  - drag from title row or original-text lines
  - panel moves immediately
- Build succeeds:
  - `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`
