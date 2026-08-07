# App Store Learning Export Entitlement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow the sandboxed Mac App Store build to export learning words to user-selected files and prevent the entitlement from regressing.

**Architecture:** Keep the existing `NSSavePanel` export flow. Grant the App Store target read/write access only to files explicitly selected by the user, keep the unsandboxed direct-distribution target unchanged, and verify both the source entitlement and resolved Release build setting.

**Tech Stack:** Xcode build settings, macOS App Sandbox entitlements, Bash, `xcodebuild`, `codesign`.

---

### Task 1: Capture the failing configuration

**Files:**
- Verify: `SnapTra Translator/SnapTra AppStore.entitlements`
- Verify: `SnapTra Translator.xcodeproj/project.pbxproj`

**Step 1:** Assert that `com.apple.security.files.user-selected.read-write` is absent from the App Store entitlement file.

**Step 2:** Assert that the App Store Release target resolves `ENABLE_USER_SELECTED_FILES` to `readonly`.

### Task 2: Grant user-selected file write access

**Files:**
- Modify: `SnapTra Translator/SnapTra AppStore.entitlements`
- Modify: `SnapTra Translator.xcodeproj/project.pbxproj`

**Step 1:** Replace `com.apple.security.files.user-selected.read-only` with `com.apple.security.files.user-selected.read-write`.

**Step 2:** Change the App Store target's Release `ENABLE_USER_SELECTED_FILES` value from `readonly` to `readwrite`.

### Task 3: Add a distribution regression check

**Files:**
- Create: `scripts/build/check-app-store-entitlements.sh`

**Step 1:** Validate a signed `.app` bundle has App Sandbox, network client, and user-selected read/write entitlements.

**Step 2:** Reject a bundle that still contains the read-only user-selected-file entitlement.

### Task 4: Verify the fix

**Step 1:** Run the relevant learning export unit tests and full-record export test.

**Step 2:** Build the App Store target in Release configuration.

**Step 3:** Run the entitlement regression script against the signed Release app.

**Step 4:** Confirm the Direct target remains unsandboxed and its entitlement file is unchanged.
