# Dual Distribution Design

**Goal:** Support both Mac App Store distribution and direct GitHub distribution with Sparkle updates without shipping Sparkle inside the App Store bundle.

**Problem Summary**

The current app target always links and embeds `Sparkle.framework`, then decides at runtime whether to use Sparkle or open the Mac App Store. That is sufficient for direct distribution, but it fails App Store validation because the submitted bundle still contains Sparkle helper executables such as `Autoupdate`, `Updater.app`, `Downloader.xpc`, and `Installer.xpc`.

The app already has Sparkle-specific host keys and sandbox exceptions configured:

- `SUPublicEDKey`
- `SUEnableInstallerLauncherService`
- `$(PRODUCT_BUNDLE_IDENTIFIER)-spks`
- `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`

Those settings are correct for sandboxed direct distribution, but they should not be present in the App Store build.

**Chosen Approach**

Split the app into two build targets that share the same source files and UI:

1. `SnapTra Translator App Store`
2. `SnapTra Translator Direct`

The Direct target links Sparkle and keeps the current Sparkle-based update flow. The App Store target does not link Sparkle at all and uses a lightweight updater implementation that redirects users to the Mac App Store.

**Why This Approach**

1. App Store compliance depends on the submitted bundle contents, not on runtime branching.
2. Sparkle is appropriate for sandboxed direct distribution, but it should be isolated to the direct build target.
3. Keeping a shared `UpdateChecker` interface minimizes app-level churn.
4. Separate plist and entitlement files keep each channel explicit and auditable.

**Implementation Shape**

1. Add a new direct-distribution target and keep the existing target for App Store distribution.
2. Move Sparkle package linkage so only the direct target depends on Sparkle.
3. Split plist and entitlement files into App Store and Direct variants.
4. Replace the current single `UpdateChecker.swift` with:
   - shared distribution-agnostic interface
   - App Store implementation without Sparkle
   - Direct implementation with Sparkle
5. Add a shared Xcode scheme for each distribution channel.
6. Update release scripts so DMG packaging and notarization only operate on the Direct scheme.

**Non-Goals**

- Migrating user settings between App Store and Direct bundle identifiers
- Adding a new updater UI
- Changing Sparkle appcast feeds or release signing format
- Building a custom in-app downloader for App Store releases

**Expected Outcome**

- App Store archives no longer include `Sparkle.framework` or its helper executables.
- Direct GitHub builds continue to support Sparkle automatic updates.
- The app keeps one shared codebase with narrowly scoped build-time differences.
