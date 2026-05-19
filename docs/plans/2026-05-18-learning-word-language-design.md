# Learning Word Language Design

## Requirement

The learning word list in Settings > Services > Learning should record the source language of each learned word, such as Chinese, English, or Japanese. Users should be able to view all words or filter the list by language.

## UI/UX Design

- Add a compact language picker beside the existing search and review-state segmented control.
- Picker options are `All Languages` plus languages found in saved learning records.
- Show a small language badge next to each word title so users can identify language without changing filters.
- Keep the existing summary cards focused on total, pending review, and mastered counts to avoid crowding the settings page.
- Existing records without language metadata display as `Unknown` and remain visible under `All Languages`.
- Exported files include a `Language` column so the language metadata follows the learning data into Anki/CSV workflows.

## Data Design

- Add `sourceLanguageIdentifier` to `WordRecord`.
- Use the resolved lookup source language (`languagePair.sourceIdentifier`) when recording a lookup.
- Preserve the current `word` unique key to keep the change minimal. If the same text is later looked up in another language, the latest source language updates the existing record.
- Treat nil or empty language identifiers as unknown for display and filtering.

## Implementation Plan

- Update `WordRecord` initialization and lookup mutation to store source language.
- Update `AppModel` to pass the resolved source language into `LearningService.recordLookup`.
- Extend `LearningService` with a language filter, dynamic language option loading, language-aware predicates, and export support.
- Update `LearningSettingsView` to maintain selected language filter, render the language picker, and show language badges in rows.
- Update `LearningExportService` to include language in export rows and headers.
- Add tests for recording source language, filtering by language, and export language output.

## Validation

- Run the relevant learning service tests.
- Run the project test suite if feasible.
- Run a Debug build if tests pass or if the test environment cannot run all tests.
