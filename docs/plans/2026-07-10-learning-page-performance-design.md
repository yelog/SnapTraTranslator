# Learning Page Performance Design

## Problem

The Learning pane becomes slow when the store approaches the supported 5,000-record limit. The current Service content owns an outer vertical `ScrollView`, while `LearningSettingsView` embeds another vertical `ScrollView` with a bottom loading sentinel. The nested layout can keep the sentinel visible and continuously drain pagination.

The data path also performs cumulative work. Every page fetch asks SwiftData for all records up to the new offset, the published model array is rebuilt by concatenation, and the view remaps every loaded record after each page. Per-row hover state adds frequent invalidation while rows move underneath a stationary pointer.

## Goals

- Show the first page without loading all matching records.
- Keep scrolling responsive with the pointer over the list.
- Preserve full-dataset counts, filters, cleanup, and matching-record export semantics.
- Use a compact Mac-native text list rather than individual card surfaces.
- Keep the feature inside Settings > Service > Learning.

## Selected Design

The Learning pane becomes the sole owner of vertical scrolling for its route. Its header, search, status filters, language filter, and management menu remain fixed while a bordered SwiftUI `List` fills the remaining height.

The three large statistic cards and the duplicate status picker are replaced by a single status picker whose labels include counts. Export, automatic-cleanup settings, cleanup-now, and clear-all move into a labeled management menu. Row actions no longer depend on hover: a pending-review action and an always-visible row menu expose the available commands, with the same commands duplicated in a context menu.

## Data Architecture

`LearningService` continues to own SwiftData access and visible records. Pagination uses a fixed `fetchLimit` plus `fetchOffset`, with a deterministic word tie-breaker after lookup count and last lookup date. The service maps only the newly fetched page into immutable `WordRecordRowModel` values and appends both records and rows incrementally.

Search is debounced in the view. Filter and language changes remain immediate and cancel a pending search reload. Export continues to execute its own unbounded matching query, independent from the visible page window.

## Performance Boundary

The first implementation stays on the main model context because removing cumulative queries, repeated remapping, nested scrolling, and per-row hover tracking addresses the dominant costs without adding concurrency risk. A dedicated SwiftData `ModelActor` is a follow-up only if Instruments still shows material fetch stalls after these changes.

## Validation

- Unit-test multi-page loading, deterministic tie sorting, row-model alignment, filters, and export scope.
- Verify the initial page contains at most 100 rows and does not automatically drain the full store.
- Build the test target and the main Debug scheme.
- Manually profile 100, 1,000, 5,000, and 10,000 records with the pointer both inside and outside the list.
