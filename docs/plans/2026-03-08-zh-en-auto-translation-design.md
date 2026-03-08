# Chinese-English Auto Translation Design

**Goal:** Add a bilingual lookup mode that lets the app detect whether the token under the cursor is Chinese or English, then translate it into the other language automatically when the user presses the shortcut.

## Problem

- The current OCR tokenization is effectively English-only.
- Chinese text can be recognized by Vision, but it is filtered out during token extraction, so it cannot be selected under the cursor.
- Translation direction is still driven by global settings, not by the actual token selected in a lookup.
- The current dictionary stack is English-centric, so Chinese-origin lookups need a clear fallback strategy.

## Product Decisions

### Scope

- This version supports only `Chinese <-> English` automatic mutual translation.
- It does not generalize automatic direction detection to every supported language pair.
- It preserves the current shortcut-driven interaction model.

### User Experience

- Users can enable an `Auto Translate` mode for the `Chinese <-> English` pair.
- When the shortcut is pressed, the app captures the region around the cursor, identifies the token under the cursor, detects whether that token is Chinese or English, and translates to the other language automatically.
- In continuous translation mode, moving the cursor across mixed Chinese and English text can switch translation direction in real time.
- If a token cannot be classified with enough confidence, the app falls back to the last successful direction, then to a default direction.

### Non-Goals

- Automatic direction detection for language pairs such as English/French or English/German.
- Chinese dictionary parity with the existing English dictionary experience.
- Replacing the current overlay interaction model or shortcut system.

## Current-State Constraints

### OCR and Tokenization

- OCR uses `VNRecognizeTextRequest` with automatic language detection enabled on supported systems.
- Token extraction is currently based on ASCII letters plus CamelCase splitting, so Chinese is not emitted as a selectable token.
- Token bounding boxes are estimated from whole-observation boxes using character ratios, which is acceptable for English but less reliable for Chinese and mixed-script text.

### Translation Direction

- Lookup code computes a source and target language per request.
- The translation bridge does not actually honor per-request direction yet because the active `TranslationSession.Configuration` is still derived from global settings.

### Downstream Consumers

- Pronunciation, dictionary preference, and language-pack checks still assume a fixed global direction.
- The advanced dictionary and WordNet are English-oriented, so Chinese-origin lookups should not block on dictionary data.

## Proposed Architecture

### 1. Token Model Upgrade

Replace the current word model with a more general token model that stores:

- token text
- normalized token bounding box
- token range within the recognized string
- script classification metadata

This allows the app to use one OCR pass for hit-testing, direction detection, and downstream behavior.

### 2. Unified Tokenization

Use `NLTokenizer(unit: .word)` for primary segmentation so Chinese and English can both produce selectable tokens.

Additional rules:

- Keep CamelCase refinement for English after the tokenizer pass.
- Drop punctuation-only tokens.
- Keep short Chinese word tokens when they contain Han characters.
- Keep English tokens with letters even if they include apostrophes or hyphens.

### 3. Better Bounding Boxes

Use the most precise token box available in this order:

1. Vision sub-range box when available and stable.
2. Measured width split fallback.
3. Current character-ratio fallback as the last resort.

The hit-test API in `AppModel` should stay simple, but the OCR layer should expose enough metadata for future refinement and debugging.

### 4. Direction Resolution Layer

Introduce a lookup-stage resolver that determines the effective translation direction from the selected token.

Rules:

- Han-character dominant token: `zh -> en`
- Latin-letter dominant token: `en -> zh`
- Mixed or ambiguous token: fall back to last successful direction
- No history available: fall back to the configured default direction

This resolved direction becomes the single source of truth for translation, pronunciation, dictionary preference, and language-pack validation for that lookup.

### 5. Request-Scoped Translation

Refactor the translation bridge so each lookup can run with its own `source` and `target`.

The request payload already carries those values, but the execution layer must stop relying on a single global `TranslationSession.Configuration`.

### 6. Settings Model

The current fixed `sourceLanguage + targetLanguage` model is not enough for mutual translation mode.

Add a mode-oriented configuration:

- language pair: `Chinese <-> English`
- translation mode: `Fixed Direction` or `Auto Mutual Translation`
- default direction: `Chinese -> English` or `English -> Chinese`

For v1, automatic mutual translation is available only when the chosen pair is Chinese and English.

### 7. Language Pack Validation

When auto mutual translation is enabled, readiness must check both directions:

- `zh -> en`
- `en -> zh`

The app should surface a clear message when one direction is missing, rather than silently failing after lookup.

## Data Flow

1. User presses the shortcut.
2. The app captures the region around the cursor.
3. OCR produces recognized observations.
4. Tokenization emits Chinese and English selectable tokens with bounding boxes.
5. Cursor hit-testing selects the best token.
6. Direction resolver classifies the token and chooses the effective source and target.
7. Translation runs with the resolved direction.
8. TTS and dictionary logic use the same resolved direction.
9. Overlay presents the token, translation, and any available dictionary data.

## Dictionary Behavior

- English-origin lookups keep the current dictionary priority behavior.
- Chinese-origin lookups should not be blocked by missing local dictionary coverage.
- If no dictionary data is available for a Chinese-origin token, the overlay still shows the translation result.
- The UI should avoid implying that Chinese-origin lookups will have the same dictionary depth as English-origin lookups.

## Error Handling

- No token under cursor: preserve current no-result behavior.
- Ambiguous script detection: use fallback direction and continue.
- Missing language pack for either required direction: show a targeted setup message.
- Translation failure: preserve current overlay error behavior.
- Missing dictionary entry: do not fail the lookup.

## Testing Strategy

### Automated

- Add unit coverage for token classification and direction resolution.
- Add unit coverage for mixed-script token filtering.
- Add unit coverage for settings-mode to effective-direction mapping.

### Manual

- English token under cursor translates to Chinese.
- Chinese token under cursor translates to English.
- Mixed Chinese/English line switches direction correctly as the cursor moves.
- Continuous translation does not get stuck in the wrong direction.
- Missing one language-pack direction produces a deterministic warning.
- Chinese-origin lookup still returns a translation even without dictionary results.

## Risks

- Chinese word segmentation can vary from user expectations for some UI strings.
- Vision token sub-range boxes may still be unstable in some fonts or rendering contexts.
- Request-scoped translation may require a larger bridge refactor than the current API shape suggests.
- Existing readiness and warmup flows currently assume one fixed direction and will need coordinated updates.

## Recommended Rollout

### Phase 1

- Support Chinese and English token selection.
- Support request-scoped translation.
- Support auto mutual translation for the Chinese/English pair.

### Phase 2

- Improve token-box precision and debugging tools.
- Revisit dictionary presentation for Chinese-origin lookups if needed.

## Success Criteria

- A user can point at either a Chinese or English token and get the opposite-language translation with the same shortcut.
- Continuous translation can move across mixed Chinese and English text without manual direction switching.
- Direction-dependent services all follow the resolved lookup direction consistently.
- Missing language-pack setup is detected before users see unexplained failures.
