# Dual Distribution Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split the app into App Store and direct-distribution builds so the App Store bundle excludes Sparkle while the direct build keeps Sparkle auto-update support.

**Architecture:** Keep one shared SwiftUI codebase and introduce two app targets with separate plist and entitlement files. Route update behavior at compile time instead of runtime: the App Store target opens the Mac App Store, while the direct target links Sparkle and uses the existing feed-driven updater flow.

**Tech Stack:** Xcode project configuration, SwiftUI macOS app, Swift Package Manager, Sparkle 2, shell release scripts

---

### Task 1: Add channel-specific bundle metadata and entitlements

**Files:**
- Create: `SnapTra Translator/Info-AppStore.plist`
- Create: `SnapTra Translator/Info-Direct.plist`
- Create: `SnapTra Translator/SnapTra AppStore.entitlements`
- Create: `SnapTra Translator/SnapTra Direct.entitlements`

**Step 1: Create the App Store plist**

Include standard bundle metadata and the screen capture usage string, but do not include any `SU*` keys or GitHub channel markers.

**Step 2: Create the Direct plist**

Start from the App Store plist and add:

- `SUPublicEDKey`
- `SUEnableInstallerLauncherService = YES`
- `DISTRIBUTION_CHANNEL = github`

**Step 3: Create the App Store entitlements**

Include:

- `com.apple.security.app-sandbox = true`
- `com.apple.security.network.client = true`
- `com.apple.security.files.user-selected.read-only = true`

Do not include Sparkle mach lookup exceptions.

**Step 4: Create the Direct entitlements**

Use the App Store entitlements and add:

- `$(PRODUCT_BUNDLE_IDENTIFIER)-spks`
- `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`

### Task 2: Split the Xcode project into App Store and Direct targets

**Files:**
- Modify: `SnapTra Translator.xcodeproj/project.pbxproj`
- Modify: `SnapTra Translator.xcodeproj/xcshareddata/xcschemes/SnapTra Translator.xcscheme`
- Create: `SnapTra Translator.xcodeproj/xcshareddata/xcschemes/SnapTra Translator Direct.xcscheme`

**Step 1: Rename the existing target role to App Store**

Keep the current target as the App Store build and point it to:

- `Info-AppStore.plist`
- `SnapTra AppStore.entitlements`

**Step 2: Duplicate the app target for Direct distribution**

Create a second app target that shares the same synchronized source group, sources, resources, and product type.

**Step 3: Attach Sparkle only to the Direct target**

Remove Sparkle package linkage from the App Store target and keep it only in the Direct target.

**Step 4: Add channel-specific build settings**

Set:

- App Store bundle identifier to the existing production identifier
- Direct bundle identifier to a distinct direct-distribution identifier
- target-specific plist and entitlements paths

**Step 5: Add separate shared schemes**

Keep `SnapTra Translator.xcscheme` pointing at the App Store target and add `SnapTra Translator Direct.xcscheme` for the direct target.

### Task 3: Split the updater implementation by compilation target

**Files:**
- Create: `SnapTra Translator/UpdateChecker.swift`
- Create: `SnapTra Translator/UpdateChecker+AppStore.swift`
- Create: `SnapTra Translator/UpdateChecker+Direct.swift`
- Delete: `SnapTra Translator/UpdateChecker.swift` (replace with split implementation)

**Step 1: Extract the shared interface**

Move the singleton, published state, interval constants, and common App Store / GitHub link helpers into a shared file with no Sparkle import.

**Step 2: Add the App Store implementation**

Implement:

- `initialize()`
- `startAutoCheckIfNeeded()`
- `updateFeedURL()`
- `checkForUpdates(...)`
- `checkForUpdatesWithUI()`

as no-op or App Store redirect behavior without Sparkle types.

**Step 3: Add the Direct implementation**

Move the existing Sparkle code into a Direct-only source file that imports `Sparkle` and preserves current feed selection behavior.

**Step 4: Assign files to the correct targets**

Ensure:

- shared updater file is in both targets
- App Store updater file is only in App Store target
- Direct updater file is only in Direct target

### Task 4: Narrow release tooling to the direct channel

**Files:**
- Modify: `scripts/build/package-app.sh`
- Modify: `scripts/build/codesign-and-notarize.sh`

**Step 1: Build the Direct scheme in packaging**

Change the package script to build `SnapTra Translator Direct` and remove the runtime metadata injection that is now provided by the direct plist.

**Step 2: Keep Sparkle validation only for the Direct build**

Validate that the packaged direct app still contains `SUPublicEDKey` and `SUEnableInstallerLauncherService`.

**Step 3: Leave signing behavior inside-out**

Retain the current non-`--deep` signing flow so nested Sparkle helpers keep valid signatures.

### Task 5: Verify both products

**Files:**
- Verify only

**Step 1: Build App Store target**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Release -destination "platform=macOS" build
```

Expected:

- build succeeds
- app bundle contains no `Sparkle.framework`

**Step 2: Build Direct target**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator Direct" -configuration Release -destination "platform=macOS" build
```

Expected:

- build succeeds
- bundle contains `Sparkle.framework`
- direct plist contains `SUPublicEDKey`

**Step 3: Run packaging smoke test**

Run:

```bash
CODESIGN_ENABLED=0 bash "scripts/build/package-app.sh"
```

Expected:

- script succeeds
- produced DMG is built from the direct scheme
