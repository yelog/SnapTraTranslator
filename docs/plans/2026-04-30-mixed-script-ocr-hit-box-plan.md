# Mixed Script OCR Hit Box Implementation Plan

> **For Claude:** Implement task-by-task in this session. Do not commit unless the user explicitly asks.

**Goal:** Make mixed Chinese and Latin OCR word lookup select the word under the cursor and draw aligned debug boxes.

**Architecture:** Keep `AppModel` and the lookup pipeline unchanged. Adjust `OCRService.resolvedTokenBoundingBox` so valid Vision subrange boxes are preferred over character-ratio fallback boxes when the fallback has drifted in mixed-script lines. Add focused XCTest coverage for the box resolver and hit-testing regression.

**Tech Stack:** Swift, Vision, NaturalLanguage, XCTest, xcodebuild

---

### Task 1: Add Box Resolution Regression Coverage

**Files:**
- Modify: `SnapTra TranslatorTests/OCRParagraphGroupingTests.swift`

**Steps:**
1. Add a test where a valid precise box for `部署` is far from a drifted fallback box but still inside the parent line.
2. Assert `OCRService.resolvedTokenBoundingBox` returns the precise box.
3. Add a selection regression with `是` and `部署` boxes proving a cursor in `部署` selects `部署`.

### Task 2: Relax Subrange Box Compatibility

**Files:**
- Modify: `SnapTra Translator/OCRService.swift`

**Steps:**
1. Keep rejecting empty or parent-escaping precise boxes.
2. For subranges, reject precise boxes that effectively cover the full parent line.
3. Remove the strict horizontal comparison against the character-ratio fallback.
4. Keep fallback behavior when no valid precise box exists.

### Task 3: Verify

**Commands:**
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/OCRParagraphGroupingTests"`
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

**Expected:**
- OCR regression tests pass.
- Debug build succeeds.
