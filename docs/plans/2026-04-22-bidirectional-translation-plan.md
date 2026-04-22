# Bidirectional Translation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an optional bidirectional translation mode that reverses the configured source and target languages when the looked-up text belongs to the target side.

**Architecture:** Persist a new bidirectional setting, add a pure lookup-direction resolver, then thread the resolved request direction through word OCR, paragraph OCR, selected-text translation, pronunciation, dictionaries, and language-pack readiness. Upgrade OCR word tokenization enough to emit both English and Chinese tokens for cursor hit-testing.

**Tech Stack:** Swift, SwiftUI, Vision, NaturalLanguage, Translation, XCTest, xcodebuild

---

### Task 1: Settings Persistence

**Files:**
- Modify: `SnapTra Translator/AppSettings.swift`
- Modify: `SnapTra Translator/SettingsStore.swift`
- Test: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Steps:**
1. Add `AppSettingKey.bidirectionalTranslationEnabled`.
2. Add `@Published var bidirectionalTranslationEnabled: Bool`.
3. Default it to `false`.
4. Persist it in `didSet` and `persistAllSettings()`.
5. Add a unit test that default is false and persistence survives reload.
6. Run `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/SettingsStoreMigrationTests"`.

### Task 2: Direction Resolver

**Files:**
- Modify: `SnapTra Translator/LookupDirection.swift`
- Test: `SnapTra TranslatorTests/LookupDirectionTests.swift`

**Steps:**
1. Add a resolver that returns the configured pair when bidirectional mode is off.
2. Add English/Chinese script matching for the configured pair.
3. Resolve English text to English-to-Chinese and Chinese text to Chinese-to-English.
4. Fall back to the configured pair for mixed or unknown text.
5. Add tests for all branches.
6. Run `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/OCRTokenClassifierTests"`.

### Task 3: OCR Tokenization

**Files:**
- Modify: `SnapTra Translator/OCRService.swift`
- Test: `SnapTra TranslatorTests/OCRParagraphGroupingTests.swift`

**Steps:**
1. Import NaturalLanguage.
2. Replace English-only token ranges with a language-aware token range helper.
3. Preserve CamelCase splitting for Latin tokens.
4. Emit Han tokens from recognized text.
5. Add tests for extracting English and Chinese tokens from plain recognized strings through test-only helper methods.
6. Run `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/OCRParagraphGroupingTests"`.

### Task 4: Runtime Integration

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`

**Steps:**
1. Change word lookup to resolve the language pair from `selected.text`.
2. Change selected-text translation to resolve from `snapshot.text`.
3. Change paragraph translation to resolve from `paragraph.text`.
4. Make required language pairs return both directions when bidirectional mode is enabled for English/Chinese.
5. Keep dictionary lookup best-effort when the effective source is not English.
6. Run lookup direction and settings tests.

### Task 5: Settings UI

**Files:**
- Modify: `SnapTra Translator/SettingsWindowView.swift`
- Modify: `SnapTra Translator/Localizable.xcstrings`

**Steps:**
1. Add a source language picker beside the target picker.
2. Add a bidirectional toggle row.
3. Refresh language status when either source or target changes.
4. Add localized strings for the new labels.
5. Build the app.

### Task 6: Final Verification

**Commands:**
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test`
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

**Manual checks:**
- Source English, target Chinese, bidirectional off: English translates to Chinese.
- Source English, target Chinese, bidirectional on: English translates to Chinese, Chinese translates to English.
- Missing reverse language pack shows the existing language-pack guidance.

