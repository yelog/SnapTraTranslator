# System Dictionary Reverse English Explanation Design

**Goal:** Ensure reverse Chinese-to-English word lookup never shows raw Chinese system-dictionary explanations when the requested output is English.

## Problem

- Bidirectional word lookup correctly reverses `zh -> en` for Chinese tokens.
- The primary translation already shows an English word.
- The system dictionary section can still render the original Chinese explanation, which makes the reverse dictionary view look incorrect.

## Root Cause

- System dictionary parsing for Chinese headwords produces definitions whose `meaning` field can still be a Chinese explanation string.
- `AppModel.translateDefinitionsInParallel` contains a fast path for `targetIsEnglish` that reuses `meaning` directly when it detects ASCII words.
- Chinese dictionary explanations often include pinyin or transliteration, so the ASCII check misclassifies the whole explanation as English and skips translation.
- When that happens, the UI uses the raw Chinese explanation as the visible translation line.

## Design

### Fast-Path Restriction

Only reuse `definition.meaning` as an English translation when the effective source language is already English.

- `en -> en` or English-origin definition content can keep the current fast path.
- `zh -> en` must not use this shortcut.

### Translation Fallback

For reverse `zh -> en` system dictionary definitions:

- Attempt actual translation through `TranslationBridge`.
- If translation fails, do not fall back to the original Chinese explanation as the English translation.
- Prefer an empty dictionary section over showing the wrong language.

## Scope

### Included

- Tighten the English fast-path condition.
- Add focused regression tests for English-source and Chinese-source cases.

### Not Included

- Deep cleaning of pinyin from Chinese explanations before translation.
- Source-specific prompt engineering for explanation translation.

## Success Criteria

- Reverse `zh -> en` lookup no longer displays raw Chinese system-dictionary explanation text as the primary dictionary translation.
- English-origin dictionary definitions still use the fast path without regression.
