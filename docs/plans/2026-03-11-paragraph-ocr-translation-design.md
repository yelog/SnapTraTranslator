# Paragraph OCR Translation Design

**Goal:** Add a paragraph translation mode that upgrades the existing word popup in place when the user double-taps the current hotkey, performs full-screen OCR on the current display, highlights the English paragraph under the pointer with green corner markers, and shows the original paragraph plus translation in the same popup.

## Problem

- The current lookup flow is optimized for single-word OCR under the pointer.
- The current hotkey lifecycle only models press and release, so it cannot upgrade an active word lookup into a paragraph lookup.
- The current screen capture path only grabs a small region around the cursor, which is insufficient for finding the full paragraph around the pointer.
- The OCR layer only returns word tokens and does not preserve line or paragraph structure.
- The popup content model is dictionary-oriented and does not support a paragraph reading layout.

## Product Decisions

### Scope

- Keep the current single-key hotkey.
- Preserve instant word lookup on the first trigger with no added delay.
- Use a second quick trigger of the same hotkey to upgrade the active popup into paragraph mode.
- In paragraph mode, OCR the full current display, locate the English paragraph under the pointer, draw green corner markers on that paragraph, and show original text above translated text in the same popup.
- Paragraph mode is one-shot. It does not participate in continuous translation.

### User Experience

- First trigger: current word lookup behavior starts immediately.
- Second trigger: the existing popup stays open and switches to a `paragraphLoading` state.
- When paragraph OCR resolves, the same popup replaces the word content with paragraph original text and paragraph translation.
- The recognized paragraph is highlighted by green right-angle corner markers so users can verify which text block was selected.

### Non-Goals

- Do not add a second popup window for paragraph results.
- Do not delay first-trigger word lookup to wait for double-tap confirmation.
- Do not add multi-display OCR in v1.
- Do not add non-English paragraph extraction rules in v1.
- Do not merge this feature with Accessibility selected-text translation in the same change.

## Current-State Constraints

### Triggering

- `HotkeyManager` currently exposes only `onTrigger` and `onRelease`.
- `AppModel` starts lookup immediately on trigger and tears everything down on release.

### Screen Capture

- `ScreenCaptureService` only supports cursor-adjacent capture around a fixed-size region.
- Full-display capture must still work within existing screen-recording permission boundaries.

### OCR

- `OCRService` tokenizes observations into English-oriented words.
- Paragraph detection must be added on top of Vision observations instead of replacing the OCR engine.

### Overlay

- `OverlayState` and `OverlayContent` represent a word-lookup result with phonetics and dictionary sections.
- `OverlayView` assumes the main result header is a single word.

## Recommended Architecture

### 1. Non-Blocking Double-Tap Upgrade

Keep first-trigger behavior unchanged and detect the second trigger as an upgrade path instead of a gated path.

- First trigger continues to call the current word lookup flow immediately.
- `HotkeyManager` records whether a short tap can participate in a double-tap window.
- If a second trigger arrives within the configured interval, it emits a new `onDoubleTap` callback without delaying the original `onTrigger`.
- `AppModel` handles `onDoubleTap` by cancelling word-specific background work and switching the same popup into paragraph mode.

This preserves current word-lookup responsiveness.

### 2. Unified Popup Shell With Multiple Content Modes

Retain one popup window and one root SwiftUI view, but extend the state model to support multiple content modes:

- `wordLoading`
- `wordResult`
- `paragraphLoading`
- `paragraphResult`
- `error`

The popup window controller remains unchanged conceptually. Only the content model and rendering logic become mode-aware.

### 3. Full-Display Capture for Paragraph Mode

Add a new screen-capture entry point that captures the full display containing the pointer.

- Use only the display under the pointer in v1.
- Downsample before OCR to keep latency reasonable on Retina displays.
- Preserve enough coordinate metadata to map paragraph bounds back into screen space for highlighting and popup anchoring.

### 4. OCR Model Upgrade From Words to Lines and Paragraphs

Extend OCR output so paragraph mode can work from the same Vision pass.

Recommended models:

- `RecognizedTextLine`
- `RecognizedParagraph`
- existing `RecognizedWord`

Paragraph detection should be geometric, not semantic. Group nearby lines into the same paragraph when they have:

- compatible line heights
- small vertical gaps
- consistent left alignment or strong horizontal overlap
- evidence they belong to the same visual column

### 5. Paragraph Hit-Testing Rules

Paragraph selection should prioritize visual correctness around the pointer.

Rules:

1. Filter to paragraphs with sufficient English content.
2. Prefer the paragraph whose bounds contain the pointer.
3. If none contain the pointer, choose the nearest paragraph only within a bounded distance.
4. If no valid English paragraph exists, show a paragraph-specific no-result message.

This prevents accidental jumps to unrelated text elsewhere on screen.

### 6. Paragraph Highlight Overlay

Promote the current debug overlay concept into a production highlight layer.

- Draw only four green right-angle corners on the selected paragraph bounding box.
- Keep the highlight separate from the popup content window.
- Use the same screen-space bounds resolved during paragraph hit-testing.

The highlight has one responsibility: confirm which paragraph is being translated.

### 7. Paragraph Presentation in the Existing Popup

Paragraph mode should replace dictionary-oriented content with a reading-oriented layout:

- top section: recognized English original text
- divider or spacing break
- bottom section: translated result
- keep copy and close actions
- omit phonetics, dictionary sections, and pronunciation playback

The popup can grow wider than word mode and should support max-height plus scrolling for long text.

### 8. Stable Positioning

To preserve the feeling of one popup upgrading in place:

- keep the popup near its current anchor when switching from word mode to `paragraphLoading`
- avoid large jumps unless the popup would heavily cover the selected paragraph
- use the paragraph highlight, not popup relocation, as the primary selection cue

## Data Flow

1. User triggers the hotkey for a word lookup.
2. `AppModel` starts the current word OCR flow immediately.
3. If the user triggers the hotkey again within the double-tap window, `HotkeyManager` emits `onDoubleTap`.
4. `AppModel` switches the popup into `paragraphLoading` without closing the window.
5. `ScreenCaptureService` captures the full display under the pointer.
6. `OCRService` recognizes text, builds lines, groups paragraphs, and chooses the English paragraph under the pointer.
7. The highlight overlay draws green corner markers around the selected paragraph.
8. `TranslationBridge` translates the selected paragraph text.
9. The popup updates to `paragraphResult` with original text and translation.
10. On hotkey release, the existing teardown path dismisses the popup and highlight.

## Performance Strategy

- Limit OCR to the display under the pointer in v1.
- Downsample capture input before OCR.
- Cancel obsolete paragraph tasks as soon as a new lookup supersedes them.
- Reuse existing request cancellation patterns in `AppModel`.

If latency remains too high after v1, evolve to a two-stage approach:

1. low-resolution full-display paragraph discovery
2. high-precision local rerecognition for the selected paragraph

## Error Handling

- Missing screen-recording permission: preserve existing permission error behavior.
- No English paragraph found under the pointer: show a paragraph-specific no-result state.
- OCR succeeds but paragraph translation fails: still show the recognized original text plus translation error state.
- User releases the hotkey while paragraph OCR is running: cancel work and dismiss popup plus highlight.
- If a newer lookup starts, stale paragraph results must be dropped using the existing lookup identity guard pattern.

## Testing Strategy

### Automated

- Add trigger-state tests for non-blocking double-tap detection.
- Add pure-model tests for paragraph grouping and pointer hit-testing.
- Add state-transition tests for upgrading from word mode to paragraph mode.
- Add overlay-view tests where practical for paragraph layout selection.

### Manual

- Trigger a normal word lookup and confirm no added delay.
- Double-trigger quickly on English body text and confirm the same popup upgrades to paragraph loading, then paragraph result.
- Verify green corner markers align with the translated paragraph.
- Verify a second trigger on non-English or empty areas yields a clear paragraph-mode no-result message.
- Verify release during paragraph OCR cancels work and hides both popup and highlight.
- Verify multi-window and full-screen app scenarios on the current display.

## Recommended Rollout

### Phase 1

- Add non-blocking double-tap upgrade plumbing.
- Add paragraph popup states.
- Add full-display capture on the current display.
- Add paragraph grouping, hit-testing, highlight, and translation.

### Phase 2

- Tune capture downsampling and paragraph grouping heuristics.
- Refine popup anchoring around large paragraphs.
- Improve detection in multi-column layouts and dense UI text.

## Success Criteria

- First-trigger word lookup remains as fast as it is today.
- Second-trigger paragraph lookup upgrades the existing popup instead of recreating it.
- The app highlights the paragraph under the pointer with green corner markers.
- The popup shows recognized paragraph original text above translated text.
- Paragraph mode fails clearly and deterministically when no valid English paragraph is found.
