# Learning Export Design

## User Need

GitHub issue #10 asks for a way to use looked-up words in Anki review. The user also accepts an Excel-style export with one column for the word and one column for its explanation.

## Fit Analysis

This project already has a learning module backed by SwiftData (`WordRecord`, `LearningService`, `LearningSettingsView`). The feature is a good fit because lookups are already recorded automatically and displayed in the learning settings page.

The current model only stores the word and review metadata. It does not persist the definition shown during lookup, so a plain export would not satisfy the core request. The implementation should persist a compact definition snapshot at lookup time, then export saved records without re-querying dictionaries.

## Approaches Considered

1. Export only existing words. This is minimal, but it misses the explanation column and is not useful for Anki cards.
2. Store a definition snapshot and export TSV/CSV. This satisfies the issue, avoids slow export-time lookups, and keeps the format layer reusable.
3. Re-query definitions during export. This could backfill old data, but it is slower, less reliable, and may produce results that differ from what the user originally saw.

## Selected Design

Use approach 2.

Add an optional `definitionText` field to `WordRecord`. When a word lookup starts, create/update the record as before. As primary translation and dictionary sections arrive, update the same record with the best compact explanation available from `OverlayContent`.

Add a small export service with two formats:

- Anki TSV: tab-separated `word`, `definition`, `lookup count`, `review stage`, and `mastered` columns. TSV is Anki-friendly because Anki imports tab-separated text directly.
- CSV: comma-separated equivalent for Numbers/Excel-style workflows.

Add export buttons to the learning settings page. The page exports the currently filtered list so users can export all words, pending review words, mastered words, or search results.

## Error Handling

If there are no words in the current filter, disable export buttons. If saving fails or the user cancels the save panel, keep the learning data unchanged. Show a short status message on successful or failed export.

## Testing

Unit-test the exporter because quoting and escaping are the risk-prone parts. Verify TSV escaping for tabs/newlines and CSV escaping for commas, quotes, and newlines.
