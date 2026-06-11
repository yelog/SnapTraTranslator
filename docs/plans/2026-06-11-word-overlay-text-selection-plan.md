# Word Overlay Text Selection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make tap-kept word overlays support drag selection and standard copy behavior for visible text.

**Architecture:** Reuse the existing AppKit-backed selectable text bridge used by sentence overlays. Add a small policy that tells `OverlayView` when word overlay text should use selectable rendering, then swap the body-level word text nodes to that rendering path.

**Tech Stack:** SwiftUI, AppKit `NSTextView`, XCTest, Xcode project build.

---

### Task 1: Add Failing Policy Test

**Files:**
- Modify: `SnapTra TranslatorTests/ParagraphOverlayLayoutTests.swift`

**Step 1: Write the failing test**

Add tests for `WordOverlayTextSelectionPolicy.usesSelectableText(...)`:

- Returns `true` when the word overlay controls are visible.
- Returns `false` when controls are hidden in passive continuous hover mode.
- Returns `false` for paragraph overlays.

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/ParagraphOverlayLayoutTests"
```

Expected: compile failure because the policy does not exist yet.

### Task 2: Implement the Policy

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift`

**Step 1: Add minimal implementation**

Create an internal `WordOverlayTextSelectionPolicy` enum near the existing overlay policies.

**Step 2: Wire `OverlayView`**

Use the policy to compute whether word overlay body text should render through selectable text views.

**Step 3: Run test to verify it passes**

Run the same focused test command and expect success.

### Task 3: Make Word Overlay Body Text Selectable

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift`

**Step 1: Add a reusable word selectable text helper**

Create `wordSelectableText(...)` around `SelectableTextView` with the same font, color, line-height, and layout behavior as the current SwiftUI text.

**Step 2: Replace body-level text**

Use the helper for:

- Header word text.
- Primary translation text.
- Dictionary translation, meaning, examples, and synonyms.
- Status and failure text where practical.

Keep badges, icons, and buttons unchanged.

**Step 3: Verify layout**

Run focused overlay tests and a Debug build.

### Task 4: Documentation and Commit

**Files:**
- Create: `docs/plans/2026-06-11-word-overlay-text-selection-design.md`
- Create: `docs/plans/2026-06-11-word-overlay-text-selection-plan.md`

**Step 1: Validate**

Run:

```bash
jq empty "SnapTra Translator/Localizable.xcstrings"
git diff --check
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

**Step 2: Commit**

Use:

```bash
git add "SnapTra Translator/OverlayView.swift" "SnapTra TranslatorTests/ParagraphOverlayLayoutTests.swift" docs/plans/2026-06-11-word-overlay-text-selection-design.md docs/plans/2026-06-11-word-overlay-text-selection-plan.md
git commit -m "fix(overlay): allow selecting kept word text"
```
