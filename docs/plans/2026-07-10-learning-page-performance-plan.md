# Learning Page Performance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the Learning settings pane fast and Mac-native at the supported 5,000-record scale without changing full matching-record export behavior.

**Architecture:** Give the Learning route one bounded list viewport, replace cumulative SwiftData pagination with a fixed offset window, and append immutable row models per page. Keep high-frequency filters fixed above a compact list and move low-frequency data operations into a management menu.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AppKit `NSSavePanel`, XCTest, macOS 14+.

---

### Task 1: Lock Pagination And Row Snapshot Behavior

**Files:**
- Modify: `SnapTra TranslatorTests/LearningServicePaginationTests.swift`
- Modify: `SnapTra Translator/LearningService.swift`
- Modify: `SnapTra Translator/LearningSettingsView.swift`

**Step 1: Write failing tests**

Add coverage that records with equal lookup count and date use word ordering as a deterministic tie-breaker. Assert that `visibleRows` always matches `visibleWords` after the first page and every appended page.

**Step 2: Run the focused test build**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -target "SnapTra TranslatorTests" -configuration Debug build
```

Expected: fail because `LearningService.visibleRows` and the stable word tie-breaker do not exist.

**Step 3: Add the minimal service state**

Publish `visibleRows`, add `SortDescriptor(\WordRecord.word, order: .forward)`, and update clear/reload paths so records and rows reset together.

**Step 4: Rebuild the test target**

Expected: the new test code compiles.

### Task 2: Replace Cumulative Pagination

**Files:**
- Modify: `SnapTra Translator/LearningService.swift:109-140`
- Test: `SnapTra TranslatorTests/LearningServicePaginationTests.swift`

**Step 1: Implement a fixed query window**

Set `fetchOffset = currentOffset` and `fetchLimit = pageSize + 1`. Use `prefix(pageSize)` as the page and `records.count > pageSize` as `hasMoreWords`.

**Step 2: Append only new data**

For subsequent pages, call `visibleWords.append(contentsOf:)` and `visibleRows.append(contentsOf:)`. Map only the current page with one shared `now` value.

**Step 3: Run the pagination test target build**

Expected: compile succeeds and existing page-count assertions remain valid.

### Task 3: Give Learning One Scroll Owner

**Files:**
- Modify: `SnapTra Translator/DictionarySettingsView.swift:401-429`
- Modify: `SnapTra Translator/LearningSettingsView.swift:23-66`

**Step 1: Split the Learning route from generic scrolling**

Render Learning directly inside the right-side `GeometryReader`, constrained to its available width and height. Keep the existing outer `ScrollView` for the other Service routes.

**Step 2: Replace the nested stack scroller**

Replace `ScrollView { LazyVStack { ... } }` with a bordered `List` that fills the remaining Learning pane height.

**Step 3: Build the app target**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected: build succeeds.

### Task 4: Redesign Learning Controls And Rows

**Files:**
- Modify: `SnapTra Translator/LearningSettingsView.swift`
- Modify: `SnapTra Translator/Localizable.xcstrings`

**Step 1: Consolidate summary and filtering**

Remove the three statistic cards. Display counts in the status picker labels and keep search, language, status, and management controls fixed above the list.

**Step 2: Add a management menu**

Move TXT, Anki, CSV, auto-cleanup settings, cleanup-now, and clear-all into one labeled menu. Present the existing auto-cleanup fields in a compact sheet.

**Step 3: Remove hover-only actions**

Delete `WordRecordRow.isHovered` and `.onHover`. Show the pending review action directly and expose all secondary actions through an always-visible ellipsis menu plus a context menu.

**Step 4: Localize new labels**

Add translations for management and automatic-cleanup settings labels in the string catalog.

### Task 5: Debounce Search And Preserve Export Scope

**Files:**
- Modify: `SnapTra Translator/LearningSettingsView.swift`
- Test: `SnapTra TranslatorTests/LearningServicePaginationTests.swift`

**Step 1: Add cancellable debounce**

Keep a view-owned search `Task`, cancel it on every keystroke, sleep for 300 milliseconds, and reload only if it was not cancelled. Cancel pending search work for immediate status or language changes and when the view disappears.

**Step 2: Preserve full export**

Keep `LearningService.exportRows` as a separate full matching query. Do not derive export rows from `visibleRows`.

**Step 3: Run focused verification**

Run the focused pagination suite with the target's display name, validate `Localizable.xcstrings` with `jq empty`, and build the Debug scheme:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug -derivedDataPath /tmp/snaptra-learning-tests test '-only-testing:SnapTra TranslatorTests/LearningServicePaginationTests'
```

### Task 6: Final Verification

**Files:**
- Verify all changed files.

**Step 1: Run whitespace checks**

```bash
git diff --check
```

**Step 2: Run the tests and build the app independently**

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug -derivedDataPath /tmp/snaptra-learning-tests test '-only-testing:SnapTra TranslatorTests/LearningServicePaginationTests'
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug -derivedDataPath /tmp/snaptra-learning-app build
```

Expected: both builds succeed.

**Step 3: Review the final diff**

Confirm there are no unrelated changes, no reduced record cap, and no export regression.
