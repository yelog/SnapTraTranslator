# Bidirectional Translation Design

**Goal:** Add an optional bidirectional mode for the configured source and target languages so the app can translate either direction from the same shortcut.

## Scope

- The setting uses the current language pair. If source is English and target is Simplified Chinese, the normal direction remains English to Chinese.
- When bidirectional mode is enabled, each lookup resolves an effective direction from the text under the cursor or selected text.
- The first implementation supports reliable script detection for English and Chinese. Other language pairs keep the fixed configured direction until explicit language detection is added.

## Current State

- `SettingsStore` already persists `sourceLanguage` and `targetLanguage`.
- `TranslationBridge` already accepts request-scoped source and target languages.
- Word OCR extraction is English-centric because token ranges are built from ASCII letters.
- Paragraph lookup names the selected result `.english`, but the translation pipeline already accepts a generic language pair.
- Dictionary sources are mostly English-origin services, so reverse Chinese-to-English lookups should not depend on dictionary results.

## Design

### Settings

Add `bidirectionalTranslationEnabled` as a persisted setting. In the General settings tab, expose:

- Translate from
- Translate to
- Bidirectional Translation

Language-pack readiness checks both directions when bidirectional mode is enabled for a detectable pair.

### Direction Resolution

Introduce a pure resolver that accepts:

- configured `sourceLanguage`
- configured `targetLanguage`
- observed text
- `bidirectionalTranslationEnabled`

It returns the effective `LookupLanguagePair`.

Rules:

- If bidirectional mode is off, return configured source to target.
- If the configured pair is English and Chinese:
  - English text resolves to English to Chinese.
  - Chinese text resolves to Chinese to English.
  - Mixed or unknown text falls back to the configured direction.
- If the pair is not supported by script detection, return configured source to target.

### OCR

Update OCR word extraction to emit both Latin word tokens and Han tokens. Use Natural Language tokenization as the primary splitter, then keep the existing CamelCase refinement for Latin words. Keep character-ratio bounding boxes for stability.

Paragraph lookup can use the recognized paragraph text for direction resolution. It does not need deep language segmentation in the first implementation.

### Downstream Behavior

Every feature uses the effective lookup direction for the current request:

- Native Translation
- third-party sentence translation
- pronunciation language
- dictionary preference
- language-pack checks

For Chinese-origin word lookup, dictionary services may return no entries. The overlay still shows the primary translation result.

## Error Handling

- Same-language effective direction returns the source text directly.
- Missing language pack surfaces the existing language-pack message.
- Unsupported language-pair detection falls back to the configured fixed direction.
- No dictionary result does not fail the lookup.

## Test Strategy

- Unit-test direction resolution for fixed, English-to-Chinese, Chinese-to-English, mixed, and unsupported pairs.
- Unit-test settings persistence and default value.
- Unit-test OCR token extraction for Latin and Han tokens.
- Unit-test language-pair requirements for bidirectional mode.

