# Sentence Original Input Design

## Background

The sentence translation overlay currently treats the detected source sentence as read-only text. Users can copy or select it, but they cannot correct OCR errors, type text manually, or paste content for translation. The overlay has two lifetimes: a temporary mode that closes when the hotkey is released, and a pinned mode that remains interactive.

## Goals

- Keep temporary sentence overlays lightweight and read-only.
- Allow editing only after the sentence overlay is pinned.
- Support typing or pasting source text, then pressing `Return` to translate.
- Preserve `Shift + Return` as multiline input.
- Keep translation results, language switching, copy actions, and overlay controls visually consistent with the existing paragraph overlay.

## UX Decision

Use one source-text region with two behaviors:

- Temporary mode: read-only source text with the existing OCR-aware font sizing.
- Pinned mode: editable source text input with stable reading/editing typography.

This avoids advertising editability in the short-lived temporary state while making the pinned state clearly usable as a manual sentence translator.

## Display Design

The editable source region should look like an inline text panel rather than a heavy form field. It uses the existing floating overlay style, adds a subtle rounded input background, and keeps the original title/copy/close controls. OCR font matching remains for read-only display, but editable input uses a fixed comfortable font size so typing does not reflow unexpectedly.

Pinned mode shows a compact hint below the input: `Return to translate · Shift-Return for line break`. Empty pinned input shows `Type or paste text to translate` as placeholder text.

## Data Flow

- OCR or selected-text lookup initializes `ParagraphOverlayContent.originalText`.
- Editing writes changes back to `originalText` without auto-translating.
- Pressing `Return` trims current input and starts a new sentence translation with the current language pair.
- Language switching continues to use the current edited source text.
- Empty input submission is ignored.

## Implementation Notes

- `AppModel` owns source text mutation and explicit submit actions.
- `OverlayView` decides whether the source region is editable from `model.isParagraphOverlayPinned`.
- A custom `NSTextView` wrapper handles multiline editing and `Return` submission reliably on macOS.
- Existing `SelectableTextView` remains available for read-only source and translated output.

## Validation

- Temporary sentence translation still closes on hotkey release and source text is not editable.
- Pinned sentence translation allows click, type, paste, select, and copy in the source field.
- `Return` re-translates edited text.
- `Shift + Return` inserts a newline.
- Switching target language after editing translates the edited text.
