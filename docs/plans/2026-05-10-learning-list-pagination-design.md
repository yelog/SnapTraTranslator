# Learning List Pagination Design

## Problem

When the learning word list contains many records, opening the Learning settings page becomes slow and can make the app feel stuck. The current flow loads every `WordRecord`, derives multiple in-memory arrays, then maps all visible records into row models during page appearance.

## Goal

Prioritize fast page opening. The Learning page should become interactive after loading only the first page of words, while search, filtering, counts, and export still operate on the full dataset.

## Current Behavior

`LearningSettingsView` calls `LearningService.refreshWords()` in `onAppear`. `refreshWords()` fetches all `WordRecord` values sorted by lookup count, then filters `pendingReviewWords` and `masteredWords` in memory. The view listens to all three published arrays and rebuilds `visibleRows` when any of them changes.

This creates several scaling problems:

- The initial SwiftData fetch is unbounded.
- Pending review and mastered lists require full in-memory scans.
- Published array updates can trigger repeated `visibleRows` rebuilds.
- `LazyVStack` avoids constructing every view immediately, but the backing data and row models are still built up front.

## Proposed Approach

Use paginated list loading backed by SwiftData predicates and database-side counts.

`LearningService` should expose UI-oriented list state instead of full cached lists:

- `visibleWords: [WordRecord]`
- `totalWordCount: Int`
- `pendingReviewCount: Int`
- `masteredCount: Int`
- `isLoadingPage: Bool`
- `hasMoreWords: Bool`

The service should load a fixed-size first page when Learning appears, then append more pages when the user reaches the end of the visible list.

## Data Flow

On page appearance:

1. Refresh summary counts using `fetchCount`.
2. Reset the paging cursor.
3. Fetch the first page for the current filter and search query.
4. Map only the fetched records into row models.

On search or filter changes:

1. Reset pagination.
2. Fetch the first page using the new predicate.
3. Keep statistics as full-dataset counts.

On scroll near the bottom:

1. Skip if `isLoadingPage` is true or `hasMoreWords` is false.
2. Fetch the next page using the same predicate and sort order.
3. Append the records to `visibleWords`.

On row actions:

1. Save the record mutation.
2. Refresh summary counts.
3. Refresh the current list window, or update/remove the affected row if the change can be applied safely.

On export:

1. Run a separate full fetch for the current filter and search query.
2. Build `LearningExportRow` from that result.
3. Do not export only the currently loaded page.

## Filtering

Filtering should move from in-memory arrays to SwiftData predicates:

- All: no status predicate.
- Pending Review: `!isMastered && nextReviewDate != nil && nextReviewDate <= now`.
- Mastered: `isMastered == true`.
- Search: `word.contains(normalizedQuery)` combined with the status predicate.

Sorting should preserve the current behavior by default: highest `lookupCount` first.

## UI Behavior

The list should show the first page quickly. When there are more records, the bottom row can show a small loading indicator or passive loading trigger. The existing empty state remains valid when the first page has no records.

The export buttons should stay enabled when the current query has matching records. If needed, the service can provide a matching count for the current filter; otherwise, the first-page result is enough for the initial implementation, because export performs its own full fetch.

## Alternatives Considered

### Background Full Load

Load the first page first, then keep loading the full dataset in the background. This improves perceived startup time but still causes memory growth and can reintroduce stutters with very large word lists.

### Minimal Refresh Reduction

Keep full-array loading but reduce repeated `visibleRows` rebuilds and debounce search. This is low risk but does not solve the core unbounded fetch and full row-model creation cost.

## Validation

Manual validation should cover:

- Opening Learning with a large word list shows the page quickly.
- Only the first page appears initially.
- Scrolling appends more records.
- Search can find words that were not in the first page.
- Pending Review and Mastered filters do not require loading all words first.
- Export includes all records matching the current filter and search query.
- Mark reviewed, mark mastered, reset, and delete keep counts and visible rows consistent.
