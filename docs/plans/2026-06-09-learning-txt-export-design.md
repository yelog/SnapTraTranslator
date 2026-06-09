# Learning TXT Export Design

## Requirement

GitHub issue #16 asks for a way to export words the user has looked up as a TXT file.

## UX Goal

Make the common, low-friction action obvious: export a plain word list that can be opened in TextEdit, copied into notes, or imported into simple study tools. Keep the existing Anki TSV and CSV workflows available for users who need richer metadata.

## Approaches Considered

1. Add a TXT button beside the existing Anki and CSV buttons. This is the most discoverable and keeps export one click away.
2. Replace all export buttons with a single export menu. This scales better if more formats are added later, but hides the new TXT action behind an extra click.
3. Add export preferences for simple TXT versus detailed TXT. This is flexible, but too heavy for the current request.

## Selected Design

Use approach 1.

Place `TXT` first in the existing `Export:` row, followed by Anki and CSV. TXT exports only the matching words, one word per line, with a trailing newline. This makes the output immediately readable and avoids turning TXT into another table format.

The export continues to respect the current learning filters: search text, review state, and source language. The UI copy should describe these as matching words instead of current words, because the export service fetches the full matching dataset rather than only the visible paginated rows.

## Data And Architecture

No model change is needed. `WordRecord` already stores looked-up words, and `LearningService.exportRows` already returns all records matching the active filters. Extend `LearningExportFormat` with a TXT case and add a formatting branch in `LearningExportService`.

## Error Handling

Keep existing behavior: disable export actions when the visible filtered list is empty, let users cancel the save panel without side effects, and show the current success or failure status message after file writes.

## Testing

Add a unit test that verifies TXT output contains only the exported words, one per line, preserves row order, and ends with a newline.
