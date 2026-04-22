# Google Dictionary Block Handling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Google dictionary failures caused by anti-bot HTML responses show an explicit failure state instead of misleading empty results.

**Architecture:** Keep transport and parsing logic mostly intact, but add a Google-specific response validator that recognizes block pages and returns typed errors. Thread those errors through dictionary lookup into the overlay section state so the UI can distinguish blocked upstream responses from true empty results.

**Tech Stack:** Swift, Foundation, URLSession, XCTest, xcodebuild

---

### Task 1: Google Response Validation

**Files:**
- Modify: `SnapTra Translator/OnlineDictionaryService.swift`

**Steps:**
1. Add typed Google lookup errors with user-facing messages.
2. Add a helper that detects HTML or known block-page markers in Google responses.
3. Make Google lookup throw for blocked or invalid non-JSON responses.

### Task 2: Error Propagation

**Files:**
- Modify: `SnapTra Translator/DictionaryService.swift`
- Modify: `SnapTra Translator/AppModel.swift`

**Steps:**
1. Change `lookupSingle` to throw typed online lookup errors.
2. Catch dictionary lookup failures in `lookupDictionarySection`.
3. Map Google failures to `.failed(message)` instead of `.empty`.

### Task 3: Regression Tests

**Files:**
- Modify: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Steps:**
1. Add a test that block-page HTML is recognized as a Google failure.
2. Add a test that ordinary JSON responses are not flagged as blocked.

### Task 4: Verification

**Commands:**
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:"SnapTra TranslatorTests/OnlineDictionaryServiceTests"`
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

**Manual checks:**
- Trigger a Google dictionary lookup on the current network.
- Confirm the Google section shows a clear failure message when upstream blocks the request.
- Confirm non-Google dictionary sections still behave as before.
