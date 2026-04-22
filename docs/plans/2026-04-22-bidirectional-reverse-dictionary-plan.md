# Bidirectional Reverse Dictionary Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make bidirectional Chinese-to-English word lookups show useful dictionary content and avoid misleading empty sections from unsupported sources.

**Architecture:** Keep the existing overlay pipeline, but filter dictionary sections by per-source direction support and fix system dictionary parser selection to follow the headword language. Extend Google lookup to supported reverse directions with the existing response parser and add focused regression tests.

**Tech Stack:** Swift, Foundation, CoreServices, SwiftUI, XCTest, xcodebuild

---

### Task 1: Direction Support Matrix

**Files:**
- Modify: `SnapTra Translator/DictionarySettingsView.swift`
- Modify: `SnapTra Translator/AppModel.swift`

**Steps:**
1. Add a per-source `supportsLookup(sourceIdentifier:targetIdentifier:)` helper.
2. Filter overlay dictionary sections to supported sources for the effective lookup direction.
3. Reuse the same filtered source list for async dictionary tasks.

### Task 2: System Dictionary Parser Fix

**Files:**
- Modify: `SnapTra Translator/DictionaryService.swift`

**Steps:**
1. Add a helper that selects the system dictionary parser from the headword language.
2. Use the general parser for Chinese headwords during reverse `zh -> en` lookup.
3. Preserve existing English-to-Chinese parsing behavior.

### Task 3: Google Reverse Lookup

**Files:**
- Modify: `SnapTra Translator/OnlineDictionaryService.swift`

**Steps:**
1. Replace the English-only Google guard with a language-code availability check.
2. Keep existing response parsing and fallback behavior.

### Task 4: Tests

**Files:**
- Modify: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Steps:**
1. Add tests for dictionary source support in `zh -> en` and `en -> zh` directions.
2. Add a test for system dictionary parser selection with a Chinese headword sample.
3. Add a test that Google source support includes reverse `zh -> en`.

### Task 5: Verification

**Commands:**
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/OnlineDictionaryServiceTests"`
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/DictionaryLookupSupportTests"`
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

**Manual checks:**
- Configure `English -> 简体中文` with bidirectional lookup enabled.
- Hover a Chinese word such as `体验` and trigger word lookup.
- Confirm the overlay keeps the primary English translation and shows only supported dictionary sections with English content.
