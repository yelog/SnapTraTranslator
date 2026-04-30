# Mixed Script OCR Hit Box Design

## Goal

Fix single-word OCR lookup in mixed Chinese and Latin text so hovering over a Chinese word selects the word under the cursor, and the debug green boxes align with the rendered text.

## Cause

`OCRService` currently validates Vision subrange boxes against fallback boxes that are calculated by splitting the full line by character count. In mixed text such as `Mysql` and `Redis` inside Chinese, character-count splitting drifts because Latin words and Han characters have different rendered widths. That drift can reject a correct Vision box and return the fallback box, so both debug boxes and hit-testing use the wrong rectangle.

## Design

Keep the existing OCR and lookup flow. Change token box resolution so Vision `boundingBox(for:)` is trusted when it is non-empty, contained within the parent observation, and not effectively the whole line for a subrange. Fall back to character-ratio boxes only when the Vision box is clearly unusable.

Keep Chinese lookup word-first. `NLTokenizer` remains responsible for Chinese word boundaries, so a cursor on `署` should resolve to `部署` when the tokenizer returns that word.

## Testing

Add focused unit coverage for mixed-script box resolution where the fallback box drifts away from a valid Vision box. Add a selection regression where the cursor in the `部署` area must not select the earlier `是` token. Run the OCR-related tests and a debug build.
