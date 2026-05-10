# Hotkey Wake Recovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent the menu bar hotkey from becoming unresponsive after long runtimes, sleep, wake, or missed modifier-key release events.

**Architecture:** Keep the fix focused on the hotkey lifecycle. `HotkeyManager` owns event-thread normalization and gesture-state recovery, while `AppModel` owns app-level sleep/wake cleanup and hotkey restart.

**Tech Stack:** Swift, AppKit `NSEvent`, `NSWorkspace` notifications, Combine, XCTest, Xcode build system.

---

### Task 1: Harden HotkeyManager Event Handling

**Files:**
- Modify: `SnapTra Translator/HotkeyManager.swift`
- Test: `SnapTra TranslatorTests/HotkeyManagerTests.swift`

**Step 1: Add a state reset test**

Add an XCTest that presses the state machine, calls `reset()`, then verifies a new press emits `.trigger`.

**Step 2: Implement minimal hotkey hardening**

Update `HotkeyManager` to:
- Dispatch global and local monitor callbacks to the main queue before mutating state or calling closures.
- Add `resetState()` to cancel pending release and reset `HotkeyGestureStateMachine`.
- Self-heal if the state machine thinks the key is down but the current modifier flags no longer contain the target modifier.

**Step 3: Run targeted tests**

Run:
```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test -only-testing:SnapTra_TranslatorTests/HotkeyManagerTests
```

Expected: hotkey tests pass.

---

### Task 2: Add App-Level Sleep/Wake Recovery

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`

**Step 1: Add recovery methods**

Add `prepareForSystemSleep()` and `recoverAfterSystemWake()` on `AppModel`.

`prepareForSystemSleep()` should reset hotkey state, stop tracking, cancel active lookup work, hide debug/highlight/overlay state, and leave the app idle.

`recoverAfterSystemWake()` should invalidate screen capture cache, clear active interaction state, restart the hotkey, and refresh permissions.

**Step 2: Register workspace notifications**

Subscribe in `bindSettings()` to `NSWorkspace.shared.notificationCenter` for:
- `willSleepNotification`
- `screensDidSleepNotification`
- `didWakeNotification`
- `screensDidWakeNotification`
- `sessionDidBecomeActiveNotification`

Sleep notifications call `prepareForSystemSleep()`. Wake/session notifications schedule `recoverAfterSystemWake()` after a short delay.

---

### Task 3: Verify Build

**Files:**
- No additional files.

**Step 1: Run full build**

Run:
```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected: build succeeds.

**Step 2: Manual verification**

Manual checks:
- Press and hold hotkey: word overlay still appears.
- Short tap release: overlay hides after double-tap window.
- Double tap: paragraph OCR still starts.
- Sleep/wake Mac, then press hotkey: app responds without restart.
