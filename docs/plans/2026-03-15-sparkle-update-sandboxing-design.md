# Sparkle Update Sandboxing Design

**Goal:** Fix the GitHub release auto-update path so Sparkle can install updates correctly in the sandboxed macOS build.

**Problem Summary**

The shipped GitHub release build is sandboxed, but its Sparkle host configuration is incomplete:

- The app bundle does not contain `SUEnableInstallerLauncherService`.
- The app entitlements do not allow Sparkle's installer connection and status mach services.
- The release signing script re-signs `Sparkle.framework` with `--deep`, which risks breaking Sparkle helper signatures and entitlements.
- The project currently relies on generated `Info.plist`, but required Sparkle keys are missing from produced release apps.

This combination allows update discovery to work but causes install launch to fail.

**Chosen Approach**

Move required Sparkle host keys into an explicit app `Info.plist`, add the sandbox mach lookup entitlements Sparkle documents for sandboxed apps, and change release signing to sign framework containers without `--deep`.

This keeps the fix narrow:

- no updater UI changes
- no feed/appcast changes
- no Sparkle API changes
- no dependency changes

**Why This Approach**

1. An explicit `Info.plist` is more reliable than relying on generated plist expansion for Sparkle-specific keys.
2. Sparkle's sandboxing docs require `SUEnableInstallerLauncherService=YES` for sandboxed apps.
3. Sparkle's installer launcher code explicitly warns against signing the app with `--deep`.
4. This restores a correct release bundle for future GitHub builds without refactoring update logic.

**Implementation Shape**

1. Add `SnapTra Translator/Info.plist` with:
   - standard bundle metadata
   - `SUPublicEDKey`
   - `SUEnableInstallerLauncherService`
2. Switch the app target from generated plist to the explicit plist.
3. Extend the app sandbox entitlements with:
   - `$(PRODUCT_BUNDLE_IDENTIFIER)-spks`
   - `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`
4. Update release packaging to validate required Sparkle keys exist before signing.
5. Update release signing to sign outer frameworks without `--deep`, preserving nested Sparkle helper signatures.

**Non-Goals**

- Repairing auto-update for already-installed broken builds without a manual reinstall
- Adding updater telemetry or new alerts
- Changing stable/beta feed selection logic

**Expected Outcome**

New GitHub release builds will include the Sparkle host settings and sandbox permissions Sparkle requires, and the release signing step will stop damaging Sparkle helper code signatures.

Users already on `v1.3.4-beta.6` or `v1.3.4-beta.7` may still need one manual DMG install to get onto a fixed host build. After that, in-app auto-update should work again.
