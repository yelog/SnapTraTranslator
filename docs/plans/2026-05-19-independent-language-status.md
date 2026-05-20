# Independent Language Status Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Always show independent selected-language availability markers beside both `Translate from` and `Translate to` in the settings language picker.

**Architecture:** Apple exposes directional pair-level availability, but the settings UI needs language-level indicators. Add UI-only probe pairs for each selected language against common languages, infer a selected language as installed when any probe involving that language is installed, and keep required-pair logic for actual translation readiness and alert priority.

**Tech Stack:** Swift, SwiftUI, Apple Translation framework status values, macOS app target `SnapTra Translator`.

---

### Task 1: Always-Two-Row Status Rendering

**Files:**
- Modify: `SnapTra Translator/SettingsWindowView.swift:717-940`

**Step 1: Add source-row indicator**

Insert `languageStatusIcon(for: .source)` before the source picker.

**Step 2: Replace target-row indicator**

Replace the old global `statusIcon` in the target row with `languageStatusIcon(for: .target)`.

**Step 3: Add row role helper**

Add a private `LanguageRole` enum inside `GeneralTranslationLanguageRow` with `source` and `target` cases.

**Step 4: Add status-pair resolution**

Add `languageStatusProbePairs` so each selected language can be checked against common languages in both directions. Deduplicate pairs by `LookupLanguagePair.key` and skip same-language probes.

**Step 5: Update status view**

Change `statusIcon` into `languageStatusIcon(for:)`, preserving the existing spinner, green check, red unavailable icon, help text, and recheck button. Derive each row from `languagePackStatus(for:)`, not directly from the currently selected language pair.

**Step 6: Refresh both display directions**

Refresh `languageStatusProbePairs` so both row icons have cached status values. Continue limiting user-facing alerts to required-pair failures so probe-only failures do not create unrelated warnings.

**Step 7: Stabilize loading state**

Track an active refresh count for the whole probe pass. While the count is greater than zero, render loading indicators only, and do not switch back to cached checkmark/cross icons until all probe checks complete.

### Task 2: Validation

**Files:**
- No source changes unless validation finds a compile issue.

**Step 1: Run Debug build**

Run: `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

Expected: `BUILD SUCCEEDED`.

**Step 2: Manual UI check**

Open Settings > General and select any source/target pair.
Expected: both rows show a checkmark or unavailable marker based on the selected language itself. If German is missing and Simplified Chinese is installed, German is red and Simplified Chinese is green.
