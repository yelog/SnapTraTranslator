# Third-Party Online Dictionaries Design

**Goal:** Add independent third-party online dictionary sources for English-to-Chinese word lookups so users can enable, disable, reorder, and compare them the same way they already do with the local advanced dictionary and the macOS system dictionary.

## Problem

- The current word dictionary source model only exposes `ecdict` and `system`.
- The UI already treats dictionary sources as separate sections with independent ordering, but no third-party online dictionary source can participate in that flow yet.
- The app already has third-party web translation experience for paragraph translation, but word lookup still cannot show richer online dictionary content such as web Chinese glosses, structured examples, or learning-oriented English definitions.

## Product Decision

- Add online dictionary providers as independent dictionary sources, not as one merged "online dictionary".
- Keep the existing user mental model:
  - one source per row in settings
  - one source per section in the overlay
  - independent enable / disable
  - independent ordering
- Optimize V1 for `English -> Chinese` single-word lookup.
- Prefer richer functionality over long-term provider stability, but keep failures isolated to the provider that failed.
- V1 provider scope:
  - `Youdao Dictionary`
  - `Google Dictionary`
  - `Free Dictionary API`
- Explicitly leave `Bing` and `DeepL` out of V1.

## Recommended Architecture

### 1. Extend the Existing Source Model

Expand `DictionarySource.SourceType` to include the new providers instead of inventing a separate online-dictionary abstraction.

Target source list:

- `system`
- `ecdict`
- `youdao`
- `google`
- `freeDictionaryAPI`

This keeps settings persistence, ordering, and overlay rendering aligned with the current code.

### 2. Keep Providers Independent End-to-End

Each enabled source should:

- appear as its own loading placeholder in the overlay
- run its own lookup task
- render its own ready / empty / failed state
- never impersonate another source on failure

The overlay should continue to preserve configured source order regardless of completion order.

### 3. Normalize Provider Output into `DictionaryEntry`

All providers should map into the existing `DictionaryEntry` model:

- `word`
- `phonetic`
- `definitions`
- `source`
- `synonyms`
- `isPretranslated`

`DictionaryEntry.Definition` remains the common rendering contract:

- `partOfSpeech`
- `field`
- `meaning`
- `translation`
- `examples`

The providers do not need to produce identical density. Missing fields should simply be absent.

### 4. Provider Roles

#### Youdao Dictionary

Role: primary rich English-to-Chinese web dictionary

Preferred content:

- phonetic
- Chinese grouped glosses by part of speech
- English definitions when available
- bilingual examples
- synonym / related-word style extras when practical

This should feel closest to a traditional Chinese-facing learner's dictionary.

#### Google Dictionary

Role: structured supplemental dictionary

Preferred content:

- part-of-speech grouped candidate translations
- structured English definitions
- example sentences

This provider is expected to be thinner than Youdao, but easier to normalize because the current endpoint returns JSON.

#### Free Dictionary API

Role: English-English fallback and learning dictionary

Preferred content:

- IPA / phonetics
- English definitions
- examples
- synonyms / antonyms
- audio URL when available

For English-to-Chinese lookups, its English definitions can still be translated through the existing definition-translation path when system translation is available. If not, the section can still render English-only content.

### 5. Best-Effort Online Fetch Layer

Introduce an online dictionary fetch layer that performs provider-specific requests and parsing without adding dependencies.

Constraints:

- use `URLSession`
- use targeted JSON decoding where possible
- use lightweight string / regex parsing for HTML fragments where necessary
- keep provider parsing code isolated so a failure in one parser does not affect other providers

## Data Flow

1. OCR resolves the selected word.
2. `AppModel` builds initial overlay content with one placeholder section per enabled dictionary source.
3. `AppModel` starts one async lookup task per enabled source.
4. `DictionaryService.lookupSingle` routes the request to the appropriate local or online provider.
5. Each provider maps raw response data into a `DictionaryEntry`.
6. Existing post-processing keeps working:
   - same-language normalization
   - definition translation for non-pretranslated entries
   - fallback primary translation extraction
7. The completed section updates in place while other sections continue loading.

## Failure Handling

- A provider timeout, parsing failure, or empty response should only mark that provider's section as `.failed` or `.empty`.
- `Youdao`, `Google`, and `Free Dictionary API` remain independent. One source must not silently fall back to another source's result.
- If an online provider returns partial data, the section should render whatever valid subset exists.
- If all enabled dictionary sources return empty or failed and no primary translation is available, the existing overlay error path can remain unchanged.

## Settings UX

The dictionary settings page should keep the current source list pattern and extend it with the online providers.

Recommended labels:

- `System Dictionary`
- `Advanced Dictionary`
- `Youdao Dictionary`
- `Google Dictionary`
- `Free Dictionary API`

Recommended subtitles:

- `macOS built-in dictionary`
- `Advanced offline dictionary`
- `Rich English-Chinese web dictionary`
- `Structured web dictionary data`
- `Free English dictionary API`

Recommended affordances:

- online providers show `Requires network`
- `Youdao` and `Google` show `Experimental`
- default state for all new online providers is disabled

## Overlay UX

- Keep the existing "one dictionary source, one section" presentation.
- Do not merge or deduplicate sections across providers.
- Continue using the shared section shell:
  - provider header
  - loading / empty / failed row
  - grouped definitions when ready
- Extend provider header title / icon mapping so the new sources are clearly labeled.

## Default Ordering

Recommended initial order after migration:

1. `Advanced Dictionary`
2. `System Dictionary`
3. `Youdao Dictionary`
4. `Google Dictionary`
5. `Free Dictionary API`

Reasoning:

- preserve today's local-first behavior
- let users opt in to richer online dictionaries without surprising defaults

## Files Likely to Change

- `SnapTra Translator/DictionarySettingsView.swift`
- `SnapTra Translator/SettingsStore.swift`
- `SnapTra Translator/DictionaryEntry.swift`
- `SnapTra Translator/DictionaryService.swift`
- `SnapTra Translator/OverlayView.swift`
- `SnapTra Translator/Localizable.xcstrings`
- new online dictionary service / parser file
- parser and settings migration tests

## Testing Strategy

- Add unit coverage for source migration and default ordering.
- Add parser-focused tests with fixed sample payloads for:
  - Youdao
  - Google
  - Free Dictionary API
- Build the app target.
- Run the relevant test target.
- Manually verify:
  - each provider can be enabled and disabled independently
  - provider order in settings matches overlay order
  - one provider failing does not block others
  - English-to-Chinese lookups still get primary translation fallback when possible

## Risks

- `Youdao` and `Google` rely on non-public web behavior and may break when the provider changes markup or payload shape.
- HTML extraction for Youdao will be more brittle than JSON parsing for Google or the Free Dictionary API.
- More enabled online providers will increase network concurrency and may make overlay height changes more noticeable if multiple sections resolve close together.

## Out of Scope

- Phrase-level or sentence-level dictionary views
- Token-based official provider APIs
- Bing or DeepL word dictionary integration in V1
- Merging multiple online providers into a single synthetic dictionary source
