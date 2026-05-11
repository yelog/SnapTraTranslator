# Learning List Pagination Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the Learning settings page open quickly with large word lists by replacing full-list loading with paginated SwiftData queries.

**Architecture:** `LearningService` will own paginated list state, full-dataset summary counts, and query construction. `LearningSettingsView` will render only the currently loaded page window, trigger reloads on search/filter changes, trigger next-page loading from the bottom row, and call a dedicated full-query export method when exporting.

**Tech Stack:** SwiftUI, SwiftData, Combine, XCTest, macOS app target `SnapTra Translator`.

---

### Task 1: Add Query State Types

**Files:**
- Modify: `SnapTra Translator/LearningService.swift`
- Modify: `SnapTra Translator/LearningSettingsView.swift`

**Step 1: Add service-level filter enum**

Move the list filter concept out of the view so the service can build queries without depending on a private view enum.

Add near the top of `LearningService.swift`, after imports:

```swift
enum LearningWordFilter: String, CaseIterable {
    case all = "All"
    case pendingReview = "Pending"
    case mastered = "Mastered"

    var title: String {
        switch self {
        case .all: return L("All Words")
        case .pendingReview: return L("Pending Review")
        case .mastered: return L("Mastered")
        }
    }
}
```

**Step 2: Replace view enum usage**

In `LearningSettingsView.swift`, remove the nested `FilterMode` enum and change:

```swift
@State private var filterMode: FilterMode = .all
```

to:

```swift
@State private var filterMode: LearningWordFilter = .all
```

Change `filterPicker` to iterate `LearningWordFilter.allCases`.

**Step 3: Build**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected: build succeeds or only fails for pre-existing unrelated issues.

### Task 2: Replace Full Cached Lists With Paginated State

**Files:**
- Modify: `SnapTra Translator/LearningService.swift`

**Step 1: Replace published arrays and counts**

Replace:

```swift
@Published var allWords: [WordRecord] = []
@Published var pendingReviewWords: [WordRecord] = []
@Published var masteredWords: [WordRecord] = []

var totalWordCount: Int { allWords.count }
var pendingReviewCount: Int { pendingReviewWords.count }
var masteredCount: Int { masteredWords.count }
```

with:

```swift
@Published var visibleWords: [WordRecord] = []
@Published var totalWordCount = 0
@Published var pendingReviewCount = 0
@Published var masteredCount = 0
@Published var isLoadingPage = false
@Published var hasMoreWords = false

private let pageSize = 100
private var currentOffset = 0
private var currentFilter: LearningWordFilter = .all
private var currentSearchText = ""
```

**Step 2: Update word lookup helper**

Change `wordRecord(for:)` to search `visibleWords`:

```swift
func wordRecord(for word: String) -> WordRecord? {
    visibleWords.first { $0.word == word }
}
```

**Step 3: Build**

Run the Debug build command.

Expected: build fails where old `allWords`, `pendingReviewWords`, or `masteredWords` are still referenced. These failures identify the view integration work for later tasks.

### Task 3: Add Count Refreshing

**Files:**
- Modify: `SnapTra Translator/LearningService.swift`

**Step 1: Add count method**

Add this method inside `LearningService`:

```swift
func refreshSummaryCounts() async {
    do {
        totalWordCount = try modelContext.fetchCount(FetchDescriptor<WordRecord>())
        pendingReviewCount = try modelContext.fetchCount(
            FetchDescriptor<WordRecord>(predicate: pendingReviewPredicate(now: Date()))
        )
        masteredCount = try modelContext.fetchCount(
            FetchDescriptor<WordRecord>(predicate: #Predicate { $0.isMastered })
        )
    } catch {
        print("Failed to fetch learning counts: \(error)")
    }
}
```

**Step 2: Add predicate helper**

Add this private helper inside `LearningService`:

```swift
private func pendingReviewPredicate(now: Date) -> Predicate<WordRecord> {
    #Predicate { record in
        !record.isMastered && record.nextReviewDate != nil && record.nextReviewDate! <= now
    }
}
```

If SwiftData predicate compilation rejects force unwrap inside the predicate, use a direct optional comparison pattern supported by the compiler in this project, or split pending count into a fetch followed by a minimal in-memory filter as a fallback.

**Step 3: Build**

Run the Debug build command.

Expected: build reaches the same old-reference failures from Task 2, with no new predicate compilation errors.

### Task 4: Add Page Query Methods

**Files:**
- Modify: `SnapTra Translator/LearningService.swift`

**Step 1: Add public reload and pagination methods**

Add:

```swift
func reloadWords(filter: LearningWordFilter, searchText: String) async {
    currentFilter = filter
    currentSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    currentOffset = 0
    hasMoreWords = false
    visibleWords = []
    await loadMoreWords()
}

func loadMoreWords() async {
    guard !isLoadingPage else { return }
    guard currentOffset == 0 || hasMoreWords else { return }

    isLoadingPage = true
    defer { isLoadingPage = false }

    do {
        var descriptor = FetchDescriptor<WordRecord>(
            predicate: listPredicate(
                filter: currentFilter,
                searchText: currentSearchText,
                now: Date()
            ),
            sortBy: [SortDescriptor(\.lookupCount, order: .reverse)]
        )
        descriptor.fetchOffset = currentOffset
        descriptor.fetchLimit = pageSize + 1

        let records = try modelContext.fetch(descriptor)
        let page = Array(records.prefix(pageSize))
        visibleWords.append(contentsOf: page)
        currentOffset += page.count
        hasMoreWords = records.count > pageSize
    } catch {
        print("Failed to fetch learning words page: \(error)")
    }
}
```

**Step 2: Add list predicate helper**

Add a private helper that combines status and search query.

Use explicit branches to keep SwiftData predicates simple:

```swift
private func listPredicate(
    filter: LearningWordFilter,
    searchText: String,
    now: Date
) -> Predicate<WordRecord>? {
    let query = searchText
    switch (filter, query.isEmpty) {
    case (.all, true):
        return nil
    case (.all, false):
        return #Predicate { $0.word.contains(query) }
    case (.pendingReview, true):
        return pendingReviewPredicate(now: now)
    case (.pendingReview, false):
        return #Predicate { record in
            record.word.contains(query)
                && !record.isMastered
                && record.nextReviewDate != nil
                && record.nextReviewDate! <= now
        }
    case (.mastered, true):
        return #Predicate { $0.isMastered }
    case (.mastered, false):
        return #Predicate { $0.isMastered && $0.word.contains(query) }
    }
}
```

If SwiftData rejects optional force unwraps in predicates, adjust the pending branches to a compiler-supported optional binding predicate. Keep the public behavior unchanged.

**Step 3: Build**

Run the Debug build command.

Expected: no predicate errors; remaining failures are view references to removed arrays and `refreshWords()`.

### Task 5: Update Mutating Operations

**Files:**
- Modify: `SnapTra Translator/LearningService.swift`

**Step 1: Add refresh helper**

Add:

```swift
private func refreshCurrentPageWindow() async {
    let loadedCount = max(currentOffset, pageSize)
    let filter = currentFilter
    let searchText = currentSearchText
    currentOffset = 0
    visibleWords = []

    repeat {
        await loadMoreWords()
    } while visibleWords.count < loadedCount && hasMoreWords

    currentFilter = filter
    currentSearchText = searchText
}
```

If this feels too broad during implementation, use the simpler path: `await reloadWords(filter: currentFilter, searchText: currentSearchText)` after each mutation.

**Step 2: Replace mutation refresh calls**

In `updateDefinition`, `markAsMastered`, `markAsReviewed`, `resetReview`, `deleteWord`, `clearAllData`, and `cleanupOldRecords`, replace `await refreshWords()` with:

```swift
await refreshSummaryCounts()
await reloadWords(filter: currentFilter, searchText: currentSearchText)
```

For `clearAllData`, it is acceptable to set `visibleWords = []`, counts to zero, and `hasMoreWords = false` after save.

**Step 3: Preserve lookup recording performance**

Do not call a full list reload from `recordLookup(word:definitionText:)`. That method is used during hotkey lookup and should stay lightweight. It may update counts only when the Learning page explicitly reloads.

**Step 4: Remove or deprecate `refreshWords()`**

Remove `refreshWords()` once all callers are updated. If another file still calls it, replace the call with `refreshSummaryCounts()` and `reloadWords(filter:searchText:)`.

**Step 5: Build**

Run the Debug build command.

Expected: remaining failures should be in `LearningSettingsView` only.

### Task 6: Update Learning Settings View Loading

**Files:**
- Modify: `SnapTra Translator/LearningSettingsView.swift`

**Step 1: Update onAppear**

Replace:

```swift
Task {
    await learningService.refreshWords()
    updateVisibleRows()
}
```

with:

```swift
Task {
    await learningService.refreshSummaryCounts()
    await learningService.reloadWords(filter: filterMode, searchText: searchText)
    updateVisibleRows()
}
```

**Step 2: Update change handlers**

Change search and filter handlers to reload from the service:

```swift
.onChange(of: searchText) { _, _ in
    Task {
        await learningService.reloadWords(filter: filterMode, searchText: searchText)
        updateVisibleRows()
    }
}
.onChange(of: filterMode) { _, _ in
    Task {
        await learningService.reloadWords(filter: filterMode, searchText: searchText)
        updateVisibleRows()
    }
}
```

**Step 3: Replace onReceive handlers**

Remove the three old receivers for `allWords`, `pendingReviewWords`, and `masteredWords`.

Add one receiver:

```swift
.onReceive(learningService.$visibleWords) { _ in
    updateVisibleRows()
}
```

**Step 4: Update filteredWords**

Replace the computed property body with:

```swift
private var filteredWords: [WordRecord] {
    learningService.visibleWords
}
```

The name can remain for minimal diff, though `loadedWords` would be clearer in a later refactor.

**Step 5: Build**

Run the Debug build command.

Expected: old full-list references are gone or limited to export.

### Task 7: Add Infinite Loading Trigger

**Files:**
- Modify: `SnapTra Translator/LearningSettingsView.swift`

**Step 1: Add bottom loading view**

Inside the `LazyVStack`, after the `ForEach(visibleRows)`, add:

```swift
if learningService.hasMoreWords || learningService.isLoadingPage {
    ProgressView()
        .controlSize(.small)
        .padding(.vertical, 8)
        .onAppear {
            Task {
                await learningService.loadMoreWords()
            }
        }
}
```

**Step 2: Avoid duplicate row-model work**

Keep `visibleRows` as the row-model cache. Do not map records inside `body`.

**Step 3: Build**

Run the Debug build command.

Expected: build succeeds or surfaces export-specific failures.

### Task 8: Make Export Full-Query Based

**Files:**
- Modify: `SnapTra Translator/LearningService.swift`
- Modify: `SnapTra Translator/LearningSettingsView.swift`

**Step 1: Add export fetch method**

In `LearningService`, add:

```swift
func exportRows(filter: LearningWordFilter, searchText: String) async -> [LearningExportRow] {
    do {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let descriptor = FetchDescriptor<WordRecord>(
            predicate: listPredicate(filter: filter, searchText: query, now: Date()),
            sortBy: [SortDescriptor(\.lookupCount, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { LearningExportRow(record: $0) }
    } catch {
        print("Failed to fetch learning export rows: \(error)")
        return []
    }
}
```

**Step 2: Update exportWords**

Change `exportWords(format:)` to start a task and fetch rows from the service before opening the save panel:

```swift
private func exportWords(format: LearningExportFormat) {
    Task {
        let rows = await learningService.exportRows(filter: filterMode, searchText: searchText)
        guard !rows.isEmpty else { return }

        let panel = NSSavePanel()
        panel.title = L("Export Learning Words")
        panel.nameFieldStringValue = "snaptra-learning-words.\(format.fileExtension)"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        do {
            let content = LearningExportService.export(rows: rows, format: format)
            try content.write(to: url, atomically: true, encoding: .utf8)
            exportResultMessage = L("Exported %lld words", rows.count)
        } catch {
            exportResultMessage = L("Export failed: %@", error.localizedDescription)
        }
    }
}
```

Because `LearningService` is `@MainActor`, this remains on the main actor. If export files become very large later, move file generation and writing off-main in a separate optimization.

**Step 3: Build**

Run the Debug build command.

Expected: build succeeds.

### Task 9: Add Service Tests Where Feasible

**Files:**
- Test: `SnapTra TranslatorTests/LearningServicePaginationTests.swift`

**Step 1: Create tests for pagination state**

Create an in-memory SwiftData container for `WordRecord`, insert at least 125 records, and verify:

- First reload returns 100 visible words.
- `hasMoreWords` is true after first reload.
- `loadMoreWords()` appends the remaining records.
- `hasMoreWords` is false after the last page.

**Step 2: Create tests for search**

Insert records where only one matching word appears outside the first 100 by lookup count. Verify `reloadWords(filter: .all, searchText: "needle")` returns that record.

**Step 3: Create tests for filters**

Insert mastered, pending review, and future review records. Verify `.mastered` and `.pendingReview` return the expected records.

If SwiftData model context setup in tests is too time-consuming or incompatible with the existing test target, skip test creation and document that the current repo has limited SwiftData test coverage for this service.

**Step 4: Run tests**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test
```

Expected: tests pass, or failure is documented if the scheme cannot run tests in the current environment.

### Task 10: Final Verification

**Files:**
- Modify only if verification finds issues.

**Step 1: Run Debug build**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected: build succeeds.

**Step 2: Manual behavior check in Xcode**

Open:

```bash
open "SnapTra Translator.xcodeproj"
```

Check:

- Learning page opens quickly.
- First page loads without freezing the settings window.
- Scrolling loads more words.
- Search can find a word that is not initially visible.
- All, Pending Review, and Mastered filters work.
- Export includes all matching words, not only visible words.

**Step 3: Review git diff**

Run:

```bash
git diff -- "SnapTra Translator/LearningService.swift" "SnapTra Translator/LearningSettingsView.swift" "SnapTra TranslatorTests/LearningServicePaginationTests.swift" docs/plans/2026-05-10-learning-list-pagination-design.md docs/plans/2026-05-10-learning-list-pagination-plan.md
```

Expected: diff is focused on learning-list pagination.
