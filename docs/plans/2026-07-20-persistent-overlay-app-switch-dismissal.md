# Persistent Overlay App Switch Dismissal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Dismiss persistent sentence and word overlays when the user activates another macOS application.

**Architecture:** Observe `NSWorkspace.didActivateApplicationNotification` because SnapTra uses nonactivating panels and cannot rely on `NSApplication` activation callbacks. Capture the source application's process identifier when persistence begins, then dismiss only when a different non-SnapTra application becomes active.

**Tech Stack:** Swift, AppKit, Combine, XCTest.

---

### Task 1: Add application activation policy

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`
- Test: `SnapTra TranslatorTests/ParagraphOverlayLayoutTests.swift`

1. Add tests for inactive overlays, source app activation, SnapTra activation, and another app activation.
2. Implement a pure activation dismissal policy.
3. Run focused tests.

### Task 2: Connect persistent overlay lifecycle

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`

1. Capture the frontmost process identifier when a sentence or tap-kept overlay becomes persistent.
2. Subscribe to workspace application activation notifications.
3. Dismiss qualifying persistent overlays through the existing cleanup path.
4. Clear the captured identifier on unpin, dismissal, or a new lookup.

### Task 3: Verify

1. Run `ParagraphOverlayLayoutTests`.
2. Run a Debug build.
3. Check the final diff and working tree.
