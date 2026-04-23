# Word OCR Bounding Box Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make OCR word lookup use accurate token boxes in mixed-script text so the shortcut selects the real word under the cursor and the debug overlay boxes line up with the rendered text.

**Architecture:** Keep the existing single-press OCR lookup flow, but change `OCRService.extractWords` to prefer Vision-derived token boxes and only fall back to the current character-ratio approximation when needed. Tighten `AppModel.selectWord` into a strict-first, tolerant-second hit-test so inaccurate expanded boxes stop stealing the cursor from nearby tokens.

**Tech Stack:** Swift, Vision, NaturalLanguage, XCTest, xcodebuild

---

### Task 1: Add OCR box extraction coverage

**Files:**
- Modify: `SnapTra TranslatorTests/OCRParagraphGroupingTests.swift`

**Steps:**
1. Add a test helper that can build `RecognizedWord` arrays with controlled bounding boxes for hit-testing scenarios.
2. Add a mixed-token word-selection regression test where the cursor is positioned over a later token and must not resolve to an earlier token.
3. Add a strict-first hit-testing test that proves overlapping expanded boxes no longer steal selection when the raw box under the cursor is different.
4. Add a tolerant fallback selection test that still resolves a nearby token when the cursor is just outside a slightly imperfect box.

### Task 2: Refactor word box generation to prefer Vision ranges

**Files:**
- Modify: `SnapTra Translator/OCRService.swift`

**Steps:**
1. Extract the per-observation word-building logic out of `extractWords` into a small helper that has access to both the `VNRecognizedTextObservation` and the top `VNRecognizedText` candidate.
2. For each token range, try to obtain a Vision-backed sub-range bounding box from the recognized text candidate.
3. Add validation for that precise box so empty or implausible rectangles are rejected.
4. Fall back to `boundingBoxByCharacterRatio` only when the precise box is unavailable or invalid.
5. Preserve the existing token filtering and script-aware refinement behavior.

### Task 3: Tighten word hit-testing

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`

**Steps:**
1. Change `selectWord(from:normalizedPoint:)` to run a strict containment pass with zero tolerance.
2. If the strict pass finds no candidates, run a second pass with a smaller tolerance than the current `0.01` expansion.
3. Keep the nearest-center tie-breaker for multiple matches in the same pass.
4. Keep the return shape unchanged so the rest of the lookup pipeline is untouched.

### Task 4: Add OCR extraction fallback tests

**Files:**
- Modify: `SnapTra TranslatorTests/OCRParagraphGroupingTests.swift`

**Steps:**
1. Add a unit-level box-generation test around the new helper surface if it can be exercised without constructing real Vision observations.
2. If the precise-box helper cannot be unit-tested directly, add focused tests for the new validation and fallback helpers instead.
3. Cover the case where a precise box is rejected and the ratio-based box is still returned.

### Task 5: Verify the change

**Commands:**
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/OCRParagraphGroupingTests"`
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

**Manual checks:**
- Enable the OCR debug region, hover on a mixed line such as `Copilot用不了了？突然不能用了`, and trigger single-press lookup: the green boxes should stay aligned with the words.
- Hover on `突` or `突然`: the selected original text should resolve to the later token rather than `用不了`.
- Hover on plain English and plain Chinese words to confirm lookup still works.
