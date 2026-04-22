# System Dictionary Reverse English Explanation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent reverse Chinese-to-English system dictionary lookups from displaying raw Chinese explanations when English output is expected.

**Architecture:** Keep the existing dictionary parsing flow, but restrict the target-English fast path so only English-source definitions can bypass translation. Leave Chinese-source reverse lookups on the normal translation path and avoid incorrect same-text fallback when translation to English is unavailable.

**Tech Stack:** Swift, Foundation, Translation, XCTest, xcodebuild

---

### Task 1: Tighten English Fast Path

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`

**Steps:**
1. Add a small helper that decides whether a definition meaning can be reused directly as an English translation.
2. Allow the fast path only when both effective source and target languages are English.
3. Remove the reverse `zh -> en` fallback that reuses the original Chinese meaning as English output.

### Task 2: Regression Tests

**Files:**
- Modify: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Steps:**
1. Add a test that English-source content still qualifies for the English fast path.
2. Add a test that Chinese-source content containing pinyin does not qualify.

### Task 3: Verification

**Commands:**
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/DictionaryDefinitionTranslationDecisionTests"`
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

**Manual checks:**
- Configure `English -> 简体中文` with bidirectional lookup enabled.
- Hover a Chinese word such as `配置`.
- Confirm the primary translation remains English and the system dictionary section no longer shows the raw Chinese explanation as the translation line.
