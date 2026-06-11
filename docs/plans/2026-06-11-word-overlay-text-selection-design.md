# Word Overlay Text Selection Design

## Problem

When "Keep Translation Bubble After Tap" is enabled, a quick tap leaves the word overlay on screen and makes the panel interactive. The panel shows copy buttons for the word and primary translation, but users cannot drag-select text in the word overlay body. Sentence overlays do not have this problem because paragraph text is rendered through an AppKit `NSTextView` wrapper.

## UX Direction

The kept word overlay should behave like a small readable document once it becomes interactive:

- Users can drag-select the word, primary translation, dictionary translations, meanings, examples, and synonyms.
- Copy buttons remain as fast one-click shortcuts for the most common copy targets.
- Part-of-speech and field badges stay non-selectable visual labels.
- Normal continuous hover lookup keeps the lightweight display behavior until the overlay is made interactive by tap-keep, non-continuous mode, or sentence mode.

This keeps the interaction consistent with sentence bubbles: any bubble that is intentionally kept on screen should support manual text selection.

## Architecture

Reuse the existing `SelectableTextView` and `SelectableTextContainerView` AppKit bridge instead of adding a second text selection system. The bridge already owns sizing, wrapping, transparent background, and AppKit text selection behavior.

Add a small word-overlay selection policy so the view layer has one readable condition for when word text should render as selectable. Then replace only body-level word overlay `Text` nodes with selectable text wrappers. Decorative badges and controls remain SwiftUI views.

## Testing

Add unit coverage for the selection policy:

- Interactive kept/non-continuous word overlays render body text as selectable.
- Passive continuous hover word overlays keep the lightweight rendering path.
- Paragraph overlays are not affected by the word policy.

Run the focused overlay tests, string catalog validation, whitespace check, and a Debug build.
