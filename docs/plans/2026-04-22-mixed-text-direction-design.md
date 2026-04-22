# Mixed Text Direction Design

**Goal:** Make bidirectional English/Chinese translation choose the effective source language from the dominant script in mixed text instead of always falling back to the configured default direction.

## Problem

- The current bidirectional resolver only distinguishes `english`, `chinese`, `mixed`, and `unknown`.
- Any text containing both Han characters and Latin letters is classified as `mixed`.
- `mixed` immediately falls back to the configured direction, even when one language is clearly dominant.
- Social text frequently includes `@handles`, URLs, and version numbers that should not influence translation direction.

## Design

### Noise Filtering

Before scoring language dominance, remove text that commonly skews detection without representing the sentence language:

- `@mentions`
- URLs
- Pure numeric runs

This keeps the change minimal while fixing the common social-media case shown in the report.

### Dominant Script Resolution

After filtering, count Han characters and English letters.

- If only one script remains, use that script directly.
- If both remain, choose the dominant script only when one side clearly exceeds the other.
- If the result is close, preserve the configured direction as a safe fallback.

The threshold should be conservative so obviously Chinese-first or English-first sentences reverse correctly, while borderline mixed strings stay stable.

## Scope

### Included

- Mixed Chinese/English dominance scoring for bidirectional direction resolution.
- Noise filtering for mentions, URLs, and numeric runs.
- Focused regression tests for dominant Chinese, dominant English, ignored mention noise, and near-tie fallback.

### Not Included

- Japanese or Korean mixed-language dominance.
- NLP-based full sentence language identification.
- UI changes to expose threshold configuration.

## Success Criteria

- A Chinese sentence containing a few English words resolves to `zh -> en` when Chinese is clearly dominant.
- An English sentence containing a few Chinese characters resolves to `en -> zh` when English is clearly dominant.
- `@mentions` and URLs do not flip the direction on their own.
- Near-tie mixed strings still fall back to the configured direction.
