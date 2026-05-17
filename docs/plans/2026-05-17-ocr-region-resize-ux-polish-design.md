# OCR Region Resize UX Polish Design

## Background

The OCR sentence region can now be resized from the green corner handles. Two interaction details still reduce precision: the cursor does not communicate diagonal corner resizing clearly, and the sentence translation panel can cover the text while the user is adjusting the OCR region.

## Goals

- Use diagonal resize cursors that match each OCR region corner.
- Hide the sentence translation panel while the user drags a green corner.
- Keep the green OCR region visible and responsive during drag.
- Restore the panel after mouse-up through the existing re-OCR loading/result flow.

## UX Direction

Dragging a corner should feel like resizing a native selection rectangle. Hovering and dragging the top-left/bottom-right handles use the northwest-southeast cursor, while top-right/bottom-left use the northeast-southwest cursor. As soon as a drag begins, the translation panel disappears so the user has an unobstructed view of the target text. On release, the app shows the normal loading panel aligned to the adjusted region and then displays the new translation.

## Behavior

- Hovering a corner sets the matching diagonal resize cursor.
- The same cursor remains active while dragging, even if the pointer leaves the small handle hit target.
- The first drag update triggers a resize-began callback.
- Resize begin hides only the translation panel window, not the overlay state or highlight window.
- Resize end keeps the existing manual-region OCR and translation behavior.

## Validation

- Cursor direction matches all four corners.
- Translation panel hides immediately when dragging starts.
- Green OCR region remains visible while dragging.
- Releasing the drag shows paragraph loading and then the updated translation.
- Debug build succeeds.
