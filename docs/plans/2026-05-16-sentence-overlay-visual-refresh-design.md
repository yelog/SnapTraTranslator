# Sentence Overlay Visual Refresh Design

## Background

The pinned sentence translation overlay now supports editing the detected source text, but the added input field makes the overlay feel like a heavy form nested inside another panel. The current design uses too many visible containers, dividers, and gray surfaces, which weakens the hierarchy between source input, language switching, and translated output.

## Goals

- Make the pinned sentence overlay feel like a native macOS floating panel.
- Keep the editable source text obvious without making it look like a large web form field.
- Give translated output stronger visual priority than utility controls.
- Reduce border, divider, and background noise.
- Preserve existing behavior: drag, copy, close, language switching, Return submit, and Shift-Return line break.

## Direction

Use one refined floating surface with soft material-like layering. The header becomes a compact toolbar, the source editor becomes an inset editing surface, the language selector becomes a quiet pill control, and the translation output becomes the main reading area.

## Visual Changes

- Header: keep `Original`, copy, drag, and close controls, but treat them as toolbar elements with lower visual weight.
- Source editor: use a subtle tinted inset background, lighter border, smaller radius, and comfortable fixed typography.
- Submit hint: move to a compact low-contrast footnote aligned with the editor instead of a full-width visual row.
- Language selector: remove the long horizontal divider lines and rely on spacing plus a compact capsule.
- Translation result: use consistent padding and readable typography so output feels like the primary content.
- Service results: keep separation, but make dividers lighter and spacing more deliberate.

## Implementation Scope

- Primary file: `SnapTra Translator/OverlayView.swift`.
- Keep data flow and model methods unchanged.
- Reuse the current `EditableParagraphTextView` and `SelectableTextView` wrappers.
- Add small SwiftUI helper views/properties only when they reduce duplication or clarify visual intent.

## Validation

- Pinned sentence overlay looks polished with editable source text.
- Temporary sentence overlay remains read-only and lightweight.
- Return still submits edited text.
- Shift-Return still inserts a newline.
- Copy, close, drag, and target language switching continue to work.
- Debug build succeeds.
