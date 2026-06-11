# Selected Text Tap Keeps Overlay Design

Date: 2026-06-11

## Summary

The existing `keepWordOverlayAfterTap` setting keeps a word lookup bubble visible after a short hotkey tap. Selected-text sentence translation enters through the same single-press route, so it should share the same tap-to-keep behavior instead of disappearing as soon as the hotkey is released.

## UX Design

Rename the visible setting label from "Keep Word Bubble After Tap" to "Keep Translation Bubble After Tap" while keeping the persisted key unchanged. The setting controls single-lookup overlays:

- OCR word lookup after a short tap.
- Selected-text sentence translation after a short tap.

Double-tap OCR paragraph translation and manual paragraph-region translation keep their existing pinned sentence overlay behavior.

When selected text is kept after a short tap, the sentence bubble becomes interactive and stays visible while translations continue loading. It dismisses with the same movement rule as the word bubble: move outside the protected overlay area by the movement threshold. The kept selected-text bubble shows a close button rather than a pin button because it is not a paragraph-region overlay.

## Implementation Notes

- Keep the existing `UserDefaults` key to preserve user settings.
- Generalize the tap-keep policy from "word lookup only" to supported single-lookup kinds.
- Keep the current async lookup task alive after release so selected-text translation results can still arrive.
- Reuse the current mouse-move dismissal path for kept overlays.

## Testing

- Add a unit test proving tap-to-keep applies to selected-text sentence lookup.
- Keep tests proving OCR paragraph lookup does not use this setting.
- Run the related hotkey, routing, settings, and overlay tests plus a Debug build.
