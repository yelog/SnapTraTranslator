# Chinese Word Tokenization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Chinese OCR hover lookup resolve the natural word under the cursor instead of treating a full sentence as one token.

**Architecture:** Keep the existing OCR lookup flow and bounding-box math, but replace the Chinese token boundary logic with `NLTokenizer(.word)` and then run the existing Latin refinement on each tokenizer-emitted range. Cover the change with focused OCR tokenization tests.

**Tech Stack:** Swift, Vision, NaturalLanguage, XCTest, xcodebuild

---

### Task 1: OCR Tokenization Update

**Files:**
- Modify: `SnapTra Translator/OCRService.swift`

**Steps:**
1. Import `NaturalLanguage`.
2. Thread the `language` argument from `recognizeWords(in:language:)` into `extractWords`.
3. Add a tokenizer-backed range enumerator using `NLTokenizer(unit: .word)`.
4. Apply the existing script-aware refinement per tokenizer range so English CamelCase splitting remains intact.
5. Add a fallback to whole-string refinement when tokenizer output is empty.

### Task 2: OCR Tokenization Tests

**Files:**
- Modify: `SnapTra TranslatorTests/OCRParagraphGroupingTests.swift`

**Steps:**
1. Add a Chinese sentence tokenization test with `language: "zh-Hans"`.
2. Verify the result contains natural-word tokens such as `为什么`, `农村`, `老年人`, and `养老金`.
3. Keep English CamelCase coverage.
4. Keep non-Latin token coverage.

### Task 3: Verification

**Commands:**
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/OCRParagraphGroupingTests"`
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

**Manual checks:**
- Source language set to Chinese, hover on a long Chinese sentence, and trigger the shortcut: only the hovered Chinese word should be translated.
- Source language set to English, hover on CamelCase or a plain English word: existing token selection still works.
