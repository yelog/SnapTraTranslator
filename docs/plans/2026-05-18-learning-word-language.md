# Learning Word Language Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Record each learning word's source language and let users view all words or filter by language.

**Architecture:** Store a source language identifier on `WordRecord`, pass it from the resolved lookup language pair, and extend `LearningService` predicates with an optional language filter. The SwiftUI settings page loads language options from saved records, adds a language picker, and shows language badges on rows.

**Tech Stack:** Swift, SwiftUI, SwiftData, XCTest, macOS app target `SnapTra Translator`.

---

### Task 1: Data And Service Tests

**Files:**
- Modify: `SnapTra TranslatorTests/LearningServicePaginationTests.swift`
- Modify: `SnapTra TranslatorTests/LookupDirectionTests.swift` only if language display helper tests are added there

**Step 1: Write failing tests**

Add tests that verify:

- `LearningService.recordLookup(word:sourceLanguageIdentifier:)` stores the source language.
- `reloadWords(filter:searchText:sourceLanguageIdentifier:)` returns only matching languages.
- Unknown records remain available when filtering all languages.

**Step 2: Run test to verify failure**

Run: `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test -only-testing:SnapTra_TranslatorTests/LearningServicePaginationTests`

Expected: FAIL because the new API and stored property do not exist yet.

### Task 2: WordRecord Language Storage

**Files:**
- Modify: `SnapTra Translator/WordRecord.swift`
- Modify: `SnapTra Translator/LearningService.swift`
- Modify: `SnapTra Translator/AppModel.swift:678-680`

**Step 1: Add storage**

Add optional `sourceLanguageIdentifier` to `WordRecord`, initialize it, and update it on lookup when provided.

**Step 2: Pass language from lookups**

Change `AppModel` to call `learningService.recordLookup(word: selected.text, sourceLanguageIdentifier: languagePair.sourceIdentifier)`.

**Step 3: Run tests**

Run the same focused test command. Expected: tests for storage pass; language filtering still fails until Task 3.

### Task 3: Language Filtering Service

**Files:**
- Modify: `SnapTra Translator/LearningService.swift`

**Step 1: Add language option model**

Add a small `LearningLanguageFilter` or equivalent value type with `all` and `language(identifier:)` semantics.

**Step 2: Load language options**

Add service state for available language identifiers derived from saved records, excluding nil/empty values.

**Step 3: Extend predicates**

Add `sourceLanguageIdentifier` to `reloadWords`, `listPredicate`, and `exportRows`. Combine language, status, and search filters.

**Step 4: Run tests**

Run the focused learning tests. Expected: PASS.

### Task 4: Settings UI

**Files:**
- Modify: `SnapTra Translator/LearningSettingsView.swift`

**Step 1: Add UI state**

Add selected language filter state and refresh/reload hooks when it changes.

**Step 2: Add picker**

Place a language picker alongside the search field and review-state segmented picker. Use `All Languages` plus service-provided language options.

**Step 3: Add row badge**

Extend `WordRecordRowModel` with language display text and render a subtle badge beside the word.

**Step 4: Preserve responsive layout**

Keep `ViewThatFits` row/stack behavior so the controls wrap cleanly in narrower settings windows.

### Task 5: Export Language Column

**Files:**
- Modify: `SnapTra Translator/LearningExportService.swift`
- Modify: tests if export tests exist or add coverage in the nearest existing test target

**Step 1: Extend protocol and row**

Add `exportSourceLanguageIdentifier` and `sourceLanguageName`/`language` field.

**Step 2: Update headers and row values**

Emit `Language` between `Word` and `Definition`.

**Step 3: Run relevant tests**

Run focused tests and ensure export output includes the language column.

### Task 6: Full Validation

**Files:**
- No source changes unless validation finds defects.

**Step 1: Run focused tests**

Run: `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test -only-testing:SnapTra_TranslatorTests/LearningServicePaginationTests`

Expected: PASS.

**Step 2: Run full tests**

Run: `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test`

Expected: PASS or report environmental failures.

**Step 3: Run build**

Run: `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

Expected: BUILD SUCCEEDED.
