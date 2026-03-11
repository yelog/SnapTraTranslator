# Overlay Smoothness Design

**Goal:** Reduce the popup's stuttery appearance while preserving incremental result updates for the main translation and dictionary sections.

## Problem Summary

The current popup feels discontinuous for three reasons:

1. The overlay content is updated incrementally, and every update re-enters the window sizing path.
2. Window movement and content-driven resizing share the same `show(at:)` path, so content updates also trigger animated frame changes.
3. Lookup cancellation is incomplete, which allows stale OCR and translation work to continue competing with the active lookup.

## Design Principles

- Keep the current incremental reveal behavior.
- Make the popup shell stable even when content arrives in waves.
- Separate popup movement from popup layout refresh.
- Cancel stale work aggressively so a new lookup is not blocked by the previous one.
- Prefer minimal, localized changes over a broader lookup-session refactor.

## Approach

### 1. Split popup responsibilities

`OverlayWindowController` should expose separate behaviors for:

- initial show
- pointer-follow movement
- content layout refresh

Content updates should no longer use the same animated frame path that is used for movement. Only the initial show should preserve the current animation behavior. Later content refreshes should update the frame only when the size actually changed, and should do so without animation.

### 2. Reduce resize churn while keeping incremental updates

`AppModel` should continue publishing partial results as each async source finishes, but window frame updates should be coalesced into a short refresh window instead of running once per section result. This keeps the visible "section-by-section" reveal while avoiding repeated synchronous layout and frame animation work.

### 3. Stabilize popup layout

`OverlayView` should keep a more stable shell:

- use a fixed width instead of a flexible min/max range
- keep loading / ready / failed rows close in vertical footprint
- preserve section order and placeholder rows so sections do not collapse and expand as aggressively

This does not remove incremental updates. It only reduces the amount of window height and origin movement caused by those updates.

### 4. Clear stale work on lookup transitions

When a new lookup starts, or when the popup is dismissed, the app should cancel stale translation requests and stop stale OCR work from continuing detached from the active task. This lowers CPU churn and prevents old work from delaying current results.

## Files to Change

- `SnapTra Translator/OverlayWindowController.swift`
- `SnapTra Translator/AppModel.swift`
- `SnapTra Translator/OverlayView.swift`
- `SnapTra Translator/OCRService.swift`
- `SnapTra Translator/TranslationService.swift`

## Expected Outcome

- The popup still appears incrementally.
- Main translation becomes visible early and stays visually stable.
- Dictionary sections still fill in progressively, but the window no longer visibly "jerks" on each update.
- Rapid pointer movement in continuous mode produces fewer stale results and less CPU contention.

## Risks

- Making the shell too stable could make the popup feel less dynamic if placeholder sizing is excessive.
- Cancelling translation requests too aggressively could accidentally suppress valid late-arriving section results if lookup identity checks are wrong.
- OCR cancellation changes must preserve current recognition correctness.

## Validation

- Single lookup: popup appears once, then fills in progressively without visible repeated frame animation.
- Continuous translation: moving across multiple words no longer causes obvious stutter or old-result bleed-through.
- Dismiss/release: closing the popup prevents stale work from affecting the next lookup.
- Build verification: `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`
