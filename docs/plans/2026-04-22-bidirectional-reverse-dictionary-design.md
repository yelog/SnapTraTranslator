# Bidirectional Reverse Dictionary Design

**Goal:** Make bidirectional word lookup show useful dictionary content for Chinese-to-English reverse lookups instead of rendering every configured source as `No result`.

## Problem

- The effective lookup direction is already reversed correctly for Chinese tokens when bidirectional lookup is enabled.
- The primary translation succeeds, but dictionary sections remain empty in reverse `zh -> en` lookups.
- This creates the false impression that bidirectional lookup is only partially working.

## Root Cause

### Source Capability Mismatch

- Most configured dictionary sources are English-origin dictionaries.
- `ECDICT` and `Free Dictionary API` only support English headwords.
- `Youdao` is currently wired only for English-to-Chinese lookups.
- `Google` is implemented conservatively and currently blocks non-English source headwords.

### System Dictionary Parser Misrouting

- System dictionary lookup currently chooses the English parser from the effective target language.
- In reverse `zh -> en` lookup this is wrong, because the looked-up headword is Chinese even though the target is English.
- That causes the parser to treat Chinese dictionary HTML as English dictionary HTML, producing no usable definitions.

## Design

### Parser Selection

Choose the system dictionary parser from the headword language, not only from the effective target language.

- English headword + English target may use the English parser.
- English headword + non-English target should keep the existing mixed parser flow.
- Chinese headword should always use the general parser so English meanings can be extracted and then rendered as English output.

### Source Support Gating

Introduce a source capability check for the effective lookup direction.

- Only show dictionary sections for sources that support the current `sourceIdentifier -> targetIdentifier` direction.
- Hide unsupported sources instead of showing misleading `No result` rows.

### Google Reverse Lookup

Allow Google dictionary lookups for supported non-English source languages when Google language codes exist for both source and target.

- This keeps the implementation minimal because the existing parser already falls back to sentence-level translation when structured dictionary sections are absent.

## Scope

### Included

- Fix system dictionary parser selection for reverse Chinese lookups.
- Filter unsupported dictionary sources from the overlay.
- Allow Google reverse lookup for supported language-code pairs.
- Add focused tests for support gating and parser selection.

### Not Included

- Adding true Chinese-headword support to `ECDICT`.
- Reworking the overlay header to account for effective target language.
- Building a new reverse-lookup-specific dictionary source.

## Success Criteria

- In English/Chinese bidirectional mode, hovering a Chinese word shows at least one dictionary section with English content.
- Unsupported sources no longer appear as `No result` during reverse lookups.
- Existing English-to-Chinese dictionary behavior does not regress.
