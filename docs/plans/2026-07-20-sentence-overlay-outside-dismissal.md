# Sentence Translation Outside Dismissal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make outside-click dismissal work consistently for persistent standard, in-place text, and in-place image sentence translations.

**Architecture:** Derive one sentence-presentation state from every supported presentation mode and use it for persistent-release and event-monitor lifecycle decisions. Pass all visible sentence-related window and source frames to one dismissal policy so clicks inside any active presentation remain interactive while clicks elsewhere dismiss the session.

**Tech Stack:** Swift, SwiftUI, AppKit `NSPanel`, `NSEvent`, XCTest.

---

### Task 1: Cover unified dismissal policy

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`
- Test: `SnapTra TranslatorTests/ParagraphOverlayLayoutTests.swift`

1. Add failing tests for in-place presentation, protected in-place frames, and non-presented sessions.
2. Run the focused test suite and verify the new cases fail.
3. Generalize the policy inputs from paragraph-only flags and fixed frames to sentence-session state and protected frames.
4. Run the focused test suite and verify it passes.

### Task 2: Unify presentation and monitoring state

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`
- Modify: `SnapTra Translator/InPlaceTranslation.swift`

1. Expose visible frames from both in-place window controllers.
2. Derive a unified sentence-translation presentation state.
3. Use that state in persistent release and outside-click monitor lifecycle decisions.
4. Include standard overlay, highlight, source, in-place text, and in-place image frames in protected frames.

### Task 3: Verify

**Files:**
- Test: `SnapTra TranslatorTests/ParagraphOverlayLayoutTests.swift`

1. Run focused policy tests.
2. Run the project Debug build.
3. Review the diff for unrelated changes and monitor cleanup regressions.

### Task 4: Preserve persistence across manual selection

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`
- Test: `SnapTra TranslatorTests/ParagraphOverlayLayoutTests.swift`

1. Add policy tests proving a persistent release is deferred while manual region interaction is active.
2. Record a one-shot pending persistence request instead of discarding it before a sentence window exists.
3. Consume the request only after a valid manual region starts its lookup.
4. Clear the request on cancellation, dismissal, a new lookup, and invalid completion.
5. Run the focused tests and Debug build.
