# OCR Region Resize Design

## Background

OCR sentence translation currently chooses a paragraph automatically from the cursor position, then shows a green corner highlight around the detected paragraph. When Vision groups text differently from the user's intent, the app can translate too little, too much, or the wrong nearby paragraph.

## Goals

- Let users correct the OCR sentence region directly by dragging the four green corners.
- Treat the adjusted rectangle as the user's explicit OCR input area.
- Trigger OCR and translation once after the user releases the drag.
- Reposition the translation panel from the adjusted rectangle.
- Preserve the existing paragraph translation panel, language selector, copy, edit, pin, and translation service behavior.

## UX Direction

The green OCR highlight remains visually lightweight, but its four corner brackets become resize handles. Pointer hover communicates resize affordance with diagonal resize cursors. During drag, the rectangle updates immediately so the user can align it with the intended text. Translation work waits until mouse-up, avoiding expensive OCR during continuous dragging.

The adjusted region is constrained to the current screen and a minimum usable size. This prevents invisible or tiny captures while still allowing precise correction. If the adjusted region contains no OCR text, the panel stays visible and shows an error so the user can adjust again.

## Behavior

- Initial double-tap OCR keeps the existing automatic paragraph selection.
- The highlight window accepts mouse events only over its resize handles.
- Dragging a corner resizes from the opposite corner.
- Mouse-up sends the final screen-space rectangle to `AppModel`.
- `AppModel` captures that rectangle, runs OCR, combines recognized lines in reading order, and translates the resulting full text.
- `activeParagraphRect` and `overlayPreferredWidth` update from the adjusted rectangle before refreshing panel layout.

## Architecture

- `OverlayWindowController.swift`: add interactive resize behavior to `ParagraphHighlightView` and a completion callback to `ParagraphHighlightWindowController`.
- `ScreenCaptureService.swift`: add a small rectangle capture API that captures a clamped screen rect using the existing ScreenCaptureKit configuration path.
- `OCRService.swift`: expose a line-combining helper for manual region OCR so the adjusted rectangle translates all text inside it.
- `AppModel.swift`: add a resize-completion handler that starts a new lookup ID, captures the selected region, updates paragraph overlay content to loading, and reuses the existing sentence translation pipeline.

## Validation

- Four green corners resize the OCR region.
- Releasing a drag triggers one OCR/translation pass.
- The translated source text comes from all recognized text inside the adjusted rectangle.
- The translation panel repositions relative to the adjusted rectangle.
- Small or off-screen drags are clamped safely.
- Debug build succeeds.
