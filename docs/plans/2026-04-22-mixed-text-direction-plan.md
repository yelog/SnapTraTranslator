# Mixed Text Direction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make bidirectional English/Chinese translation choose direction from the dominant script in mixed text after filtering common social-media noise.

**Architecture:** Keep the existing `LookupLanguagePairResolver` entry point, but replace the `mixed -> fallback` branch with a dominant-script scorer. The scorer removes mentions, URLs, and numeric runs, then compares Han and English character counts with a conservative threshold. Add focused resolver tests without touching the translation pipeline.

**Tech Stack:** Swift, Foundation, XCTest, xcodebuild

---

### Task 1: Dominant Script Scoring

**Files:**
- Modify: `SnapTra Translator/LookupDirection.swift`

**Steps:**
1. Add helpers to strip mentions, URLs, and numeric runs from observed text.
2. Count Han characters and English letters in the filtered text.
3. Return the dominant language family when one script clearly exceeds the other.
4. Preserve the existing fallback when the filtered text is empty or too balanced.

### Task 2: Resolver Integration

**Files:**
- Modify: `SnapTra Translator/LookupDirection.swift`

**Steps:**
1. Switch `LookupLanguagePairResolver.resolve` to use the new dominant-script helper.
2. Keep the existing behavior for unsupported language pairs and disabled bidirectional mode.
3. Preserve the current forward/reverse mapping once a dominant family is known.

### Task 3: Regression Tests

**Files:**
- Modify: `SnapTra TranslatorTests/LookupDirectionTests.swift`

**Steps:**
1. Add a test for a Chinese-dominant mixed sentence.
2. Add a test for an English-dominant mixed sentence.
3. Add a test showing `@mentions` and URLs do not affect direction.
4. Add a test for near-tie fallback to the configured direction.

### Task 4: Verification

**Commands:**
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/OCRTokenClassifierTests"`
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

**Manual checks:**
- Enable bidirectional translation for `English -> 简体中文`.
- Select or OCR a Chinese sentence containing a small English fragment such as `Kimi 2.6`.
- Confirm the effective result is translated to English instead of staying in Chinese.
