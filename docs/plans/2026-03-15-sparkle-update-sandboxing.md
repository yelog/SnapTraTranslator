# Sparkle Update Sandboxing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restore Sparkle install-time auto-update behavior for sandboxed GitHub release builds.

**Architecture:** Replace the generated host bundle plist with an explicit plist that includes Sparkle host keys, add Sparkle's required sandbox mach lookup exceptions to the app entitlements, and stop deep re-signing `Sparkle.framework` during release packaging. Add a release-script validation step so future GitHub builds fail fast if required Sparkle config is missing.

**Tech Stack:** SwiftUI macOS app, Xcode project settings, Sparkle 2, shell build scripts, codesign

---

### Task 1: Make Sparkle host keys explicit in the app bundle

**Files:**
- Create: `SnapTra Translator/Info.plist`
- Modify: `SnapTra Translator.xcodeproj/project.pbxproj`

**Step 1: Add an explicit app Info.plist**

Create `SnapTra Translator/Info.plist` with:

- `CFBundleDisplayName = $(PRODUCT_NAME)`
- `CFBundleIdentifier = $(PRODUCT_BUNDLE_IDENTIFIER)`
- `CFBundleShortVersionString = $(MARKETING_VERSION)`
- `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`
- `LSMinimumSystemVersion = $(MACOSX_DEPLOYMENT_TARGET)`
- `ITSAppUsesNonExemptEncryption = NO`
- `LSApplicationCategoryType = public.app-category.productivity`
- `SUPublicEDKey = OJo/oEqSjtmok1HYx+XgFHLq1FkUAJs8hsDms0+Uv98=`
- `SUEnableInstallerLauncherService = YES`

**Step 2: Point the app target at the explicit plist**

Modify the app target build settings in `SnapTra Translator.xcodeproj/project.pbxproj`:

- set `GENERATE_INFOPLIST_FILE = NO`
- set `INFOPLIST_FILE = "SnapTra Translator/Info.plist"`

**Step 3: Build the Release app**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Release -destination "platform=macOS" -derivedDataPath /tmp/snaptra-dd build
```

Expected:

- build succeeds
- `/tmp/snaptra-dd/Build/Products/Release/SnapTra Translator.app/Contents/Info.plist` contains `SUPublicEDKey`
- the same plist contains `SUEnableInstallerLauncherService = true`

### Task 2: Add Sparkle sandbox communication entitlements

**Files:**
- Modify: `SnapTra Translator/Snap Translate.entitlements`

**Step 1: Add Sparkle mach lookup exceptions**

Add:

```xml
<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
<array>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
</array>
```

**Step 2: Rebuild and inspect signed entitlements**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Release -destination "platform=macOS" -derivedDataPath /tmp/snaptra-dd build
codesign -d --entitlements :- "/tmp/snaptra-dd/Build/Products/Release/SnapTra Translator.app" 2>/dev/null
```

Expected:

- the signed app entitlements include sandbox, network client, and the `spks` / `spki` lookup names

### Task 3: Stop deep re-signing Sparkle.framework

**Files:**
- Modify: `scripts/build/codesign-and-notarize.sh`

**Step 1: Replace deep framework signing**

Change framework signing from:

```bash
codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" --timestamp "$framework"
```

to:

```bash
codesign --force --options runtime --sign "$SIGNING_IDENTITY" --timestamp "$framework"
```

Add a short comment explaining Sparkle helper signatures must be preserved.

**Step 2: Validate the behavior with a local signing smoke test**

Run:

```bash
bash "scripts/build/codesign-and-notarize.sh" sign "/tmp/snaptra-dd/Build/Products/Release/SnapTra Translator.app"
codesign --verify --deep --strict --verbose=2 "/tmp/snaptra-dd/Build/Products/Release/SnapTra Translator.app"
```

Expected:

- signing succeeds
- verification succeeds
- `Sparkle.framework/Autoupdate` still has a valid code signature after the app is signed

### Task 4: Fail fast when required Sparkle keys are missing from GitHub builds

**Files:**
- Modify: `scripts/build/package-app.sh`

**Step 1: Add release-time Sparkle config validation**

After GitHub distribution metadata is injected, add checks that:

- `SUPublicEDKey` exists
- `SUEnableInstallerLauncherService` exists and is `true`

If either check fails, exit with a clear error.

**Step 2: Run the packaging script without notarization**

Run:

```bash
DISTRIBUTION_CHANNEL=github CODESIGN_ENABLED=0 bash "scripts/build/package-app.sh"
```

Expected:

- build succeeds
- script does not fail the Sparkle validation step
- `dist/DerivedData/Build/Products/Release/SnapTra Translator.app/Contents/Info.plist` contains both required Sparkle keys

### Task 5: Perform final release-bundle verification

**Files:**
- Verify only

**Step 1: Sign the packaged app bundle**

Run:

```bash
bash "scripts/build/codesign-and-notarize.sh" sign "dist/DerivedData/Build/Products/Release/SnapTra Translator.app"
```

**Step 2: Inspect the final bundle**

Run:

```bash
/usr/libexec/PlistBuddy -c "Print :SUEnableInstallerLauncherService" "dist/DerivedData/Build/Products/Release/SnapTra Translator.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "dist/DerivedData/Build/Products/Release/SnapTra Translator.app/Contents/Info.plist"
codesign -d --entitlements :- "dist/DerivedData/Build/Products/Release/SnapTra Translator.app" 2>/dev/null
codesign --verify --deep --strict --verbose=2 "dist/DerivedData/Build/Products/Release/SnapTra Translator.app"
```

Expected:

- bundle contains both Sparkle keys
- bundle entitlements include the Sparkle mach lookup exceptions
- deep verification succeeds
