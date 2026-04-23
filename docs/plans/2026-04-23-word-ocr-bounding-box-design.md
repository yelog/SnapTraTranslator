# Word OCR Bounding Box Design

**Goal:** Make single-press OCR word lookup select the actual word under the cursor in mixed-script text, and keep the debug OCR boxes visually aligned with that word.

## Scope

- The fix only applies to single-press OCR word lookup.
- It covers both cursor hit-testing and the debug OCR word rectangles because they share the same `RecognizedWord.boundingBox` data.
- It does not change selected-text lookup, paragraph OCR lookup, translation services, or dictionary rendering.

## Current State

- `AppModel.performOcrWordLookup` captures a region around the cursor, normalizes the cursor position, runs OCR, and selects a word by testing the cursor against `RecognizedWord.boundingBox` values.
- The debug overlay uses those same word bounding boxes to draw the green rectangles shown in the OCR region preview.
- `OCRService.extractWords` currently tokenizes observation text, then computes each token box with `boundingBoxByCharacterRatio`.
- That ratio-based calculation splits the full observation width by string character offsets instead of using the real glyph positions returned by Vision.

## Problem

Mixed-script lines such as `Copilot用不了了？突然不能用了` accumulate horizontal error when token boxes are derived from full-line character ratios.

- Latin letters, Han characters, punctuation, and variable-width fonts do not occupy equal visual width.
- When the full observation width is divided by character count, later tokens drift farther from their real screen position.
- The debug overlay therefore draws shifted boxes.
- `AppModel.selectWord` then hit-tests against those shifted boxes, so the cursor can land on `突` while the selection still resolves to the earlier token `用不了`.

## Design

### Bounding Box Source

Change `OCRService.extractWords` so it prefers Vision-provided sub-range bounding boxes before falling back to the existing ratio-based approximation.

- For each `VNRecognizedTextObservation`, get the top `VNRecognizedText` candidate.
- Use the tokenizer result to identify token ranges inside the recognized string.
- For each token range, first ask Vision for a sub-range bounding box derived from the recognized text.
- Accept that box only when it is non-empty and plausibly contained within the parent observation bounds.
- If Vision does not return a usable sub-range box, fall back to the existing `boundingBoxByCharacterRatio` behavior.

### Token Refinement

Keep the current tokenization approach and language-aware splitting behavior.

- Continue using `NLTokenizer(unit: .word)` plus the existing script-aware refinement.
- Preserve the current CamelCase refinement for Latin tokens.
- Avoid a larger redesign of OCR tokenization because the current bug is primarily a box-generation issue, not a token-boundary issue.

### Word Selection

Tighten cursor hit-testing so the lookup favors precise matches first.

- First pass: require the cursor point to be inside the raw token box with no tolerance.
- Second pass: only if nothing matches, retry with a smaller expansion tolerance.
- If multiple boxes still match in either pass, keep the existing nearest-center tie-breaker.

This keeps slightly imperfect OCR boxes usable while reducing false positives caused by overlapping expanded rectangles.

## Error Handling

- If Vision sub-range extraction fails for a token, immediately fall back to the ratio-based box for that token instead of dropping it.
- If a Vision sub-range box is empty, outside the parent observation, or otherwise invalid, treat it as unusable and fall back.
- If no boxes match in strict mode, the tolerant second pass preserves current resilience for imperfect OCR output.

## Test Strategy

- Add focused OCR extraction tests that cover mixed-script text and verify token boxes remain ordered and locally aligned.
- Add word-selection tests for the case where the cursor is on a later token and must not resolve to an earlier token.
- Add a fallback test that verifies ratio-based boxes are still emitted when precise sub-range boxes are unavailable.
- Run the focused OCR-related tests and a full debug build.

## Acceptance Criteria

- Hovering the cursor over `突` in a mixed-script sentence resolves the later token near `突然`, not the earlier token `用不了`.
- The debug green OCR rectangles visibly align with the rendered words instead of drifting farther right or left across the line.
- Pure English and pure Chinese OCR word lookup continue to work.
- No changes are required in paragraph lookup or selected-text lookup.
