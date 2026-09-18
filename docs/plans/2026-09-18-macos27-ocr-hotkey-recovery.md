# macOS 27 OCR and Hotkey Recovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement the plan task-by-task.

**Goal:** Make screen OCR resilient to macOS 27 screenshot image changes and make standalone modifier hotkeys reliably detect physical press/release events.

**Architecture:** Keep the existing macOS 14-compatible Vision API for now, but normalize every ScreenCaptureKit image into a standard sRGB bitmap before OCR. Add structured diagnostics at capture/OCR boundaries and track the configured modifier by physical key code rather than aggregate modifier flags.

**Tech Stack:** Swift, AppKit, ScreenCaptureKit, Vision, OSLog, XCTest.

---

### Task 1: Harden OCR input and diagnostics

**Files:**
- Modify: `SnapTra Translator/OCRService.swift`
- Modify: `SnapTra Translator/ScreenCaptureService.swift`
- Modify: `SnapTra Translator/AppModel.swift`

Add standard bitmap normalization, OCR request metadata logging, and capture error propagation/logging without exposing recognized text or credentials.

### Task 2: Fix physical modifier hotkey state

**Files:**
- Modify: `SnapTra Translator/HotkeyManager.swift`
- Modify: `SnapTra TranslatorTests/HotkeyManagerTests.swift`

Use the configured modifier key's keyCode as the source of truth for press/release and add recovery when a release event is lost.

### Task 3: Verify

Run the hotkey tests, the full test suite, and a Debug build. Confirm the changed code compiles against the project's macOS 14 deployment target.
