# Overlay Smoothness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep the translation popup's incremental reveal behavior while removing the visible stutter caused by repeated frame animation, stale async work, and unstable popup layout.

**Architecture:** Separate popup movement from popup layout refresh, then coalesce content-driven frame updates. Keep incremental overlay state updates, but cleanly cancel stale OCR and translation work when lookups change so the active lookup remains responsive.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Concurrency, Translation, Vision

---

### Task 1: Split popup movement from popup layout refresh

**Files:**
- Modify: `SnapTra Translator/OverlayWindowController.swift`

**Step 1: Add explicit window update paths**

Create separate methods for:

- initial show at an anchor
- movement-only updates
- layout refresh updates

Keep the existing anchor clamping logic, but make layout refresh compare the new frame to the current frame before applying it.

**Step 2: Keep initial show behavior lightweight**

Preserve immediate first render behavior for a hidden window, but remove animated frame changes from content refreshes.

**Step 3: Add a small frame comparison tolerance**

Only apply a frame update when the delta is visually meaningful to avoid redundant size churn.

**Step 4: Build-check this file through app build**

Run: `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

Expected: build succeeds with the new controller API.

### Task 2: Coalesce overlay refreshes and clear stale requests

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`
- Modify: `SnapTra Translator/TranslationService.swift`

**Step 1: Route state updates and frame refresh separately**

Keep `overlayState` updates immediate, but stop calling the same popup show path for every `.result` mutation.

**Step 2: Add short refresh coalescing**

Introduce a brief delayed layout refresh mechanism so multiple section completions close together produce one frame refresh instead of several back-to-back refreshes.

**Step 3: Clear stale translation requests on lookup transitions**

When starting a new lookup, releasing the hotkey, or dismissing the popup, cancel pending translation bridge requests before new work begins.

**Step 4: Preserve incremental reveal semantics**

Do not batch results into a final payload. Main translation and dictionary sections should still appear independently.

### Task 3: Stabilize popup shell layout

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift`

**Step 1: Make popup width stable**

Replace the current min/max width sizing with a fixed preferred width that matches the current design.

**Step 2: Reduce avoidable height swings**

Keep loading, ready, empty, and failed rows closer in footprint so the content shell remains visually steady as sections update.

**Step 3: Keep dictionary section placeholders compact**

Retain section ordering and compact placeholder rows so progressive updates remain obvious without causing excessive reflow.

### Task 4: Make OCR work cancellable

**Files:**
- Modify: `SnapTra Translator/OCRService.swift`

**Step 1: Remove detached OCR execution**

Replace `Task.detached` with a cancellation-aware task structure that inherits cancellation from the active lookup.

**Step 2: Add explicit cancellation checkpoints**

Check cancellation before expensive OCR work and before returning results.

**Step 3: Verify lookup cancellation still behaves correctly**

Confirm rapid pointer movement or quick release does not leave OCR work running unnecessarily.

### Task 5: Verify behavior

**Files:**
- No new files required unless small helper comments are needed

**Step 1: Build the app**

Run: `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

Expected: `BUILD SUCCEEDED`

**Step 2: Manual verification**

Check:

- popup appears once and stays visually stable
- main translation still appears before slower dictionary sections
- dictionary sections still reveal incrementally
- rapid continuous translation no longer produces obvious old-result bleed or repeated frame stutter
- releasing the hotkey stops further visible updates

**Step 3: Summarize residual risk**

If build succeeds but no UI automation is available, document that final confirmation is manual for popup smoothness.
