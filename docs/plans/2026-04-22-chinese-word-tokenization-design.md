# Chinese Word Tokenization Design

**Goal:** Make Chinese hover lookup tokenize OCR text into natural words so the shortcut translates the word under the cursor instead of the whole sentence.

## Scope

- The fix applies to OCR word lookup triggered by the single-press shortcut.
- Chinese source languages should prefer word-level segmentation such as `老年人` and `养老金`.
- English and mixed-script OCR handling should keep the current behavior, including CamelCase refinement.

## Current State

- `AppModel.performOcrWordLookup` calls `OCRService.recognizeWords(in:language:)` and passes the configured source language.
- `OCRService.extractWords` currently ignores that language hint and always tokenizes with the same script-aware splitter.
- The current splitter keeps contiguous Han text as one token, so a whole Chinese sentence produces one large bounding box.
- Cursor hit-testing then selects that entire sentence because `AppModel.selectWord` works on the emitted token boxes.

## Design

### Tokenization

Use `NLTokenizer(unit: .word)` as the primary word splitter inside `OCRService`.

- When a source language hint is available, set the tokenizer language from that hint.
- Enumerate word ranges from the full OCR observation text.
- Refine each tokenizer-emitted range with the existing script-aware logic so Latin text still supports CamelCase splitting.
- Keep Han ranges intact after tokenizer segmentation so the tokenizer decides the natural Chinese word boundaries.

### Bounding Boxes

Keep the existing character-ratio bounding box calculation.

- It already works on arbitrary `Range<String.Index>` values.
- It avoids expanding the scope into Vision sub-range bounding-box instability.

### API Shape

- Thread `language` through `extractWords`.
- Add a language-aware `tokenTexts(in:language:)` helper for tests.
- Preserve the existing zero-argument test helper as a convenience wrapper if useful.

## Error Handling

- If `NLTokenizer` cannot infer or accept a language, it still enumerates words with its default behavior.
- If tokenization returns no ranges for non-empty text, fall back to the existing script-aware splitter across the whole string.
- Pure numeric tokens continue to be filtered out by the existing `containsLetter` guard.

## Test Strategy

- Add a Chinese sentence test that verifies multi-word token output instead of a single sentence token.
- Keep coverage for English CamelCase splitting.
- Keep coverage for non-Latin, non-Chinese letter tokens so fixed-language lookups do not regress.
