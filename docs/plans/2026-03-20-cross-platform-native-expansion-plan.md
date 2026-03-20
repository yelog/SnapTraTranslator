# Cross-Platform Native Expansion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor the existing macOS-first codebase just enough to support native Windows and Linux shells later, without changing the current macOS App Store feature behavior.

**Architecture:** Keep the existing macOS app target as the stable shell and introduce protocol-driven service boundaries around capture, OCR, translation, dictionary, speech, hotkeys, and permissions. Extract only pure models and pure text logic first, then let future Windows and Linux implementations satisfy the same contracts.

**Tech Stack:** Swift, SwiftUI, AppKit, local Swift Package or shared source group, SQLite3, Xcode project configuration, future WinUI 3 / GTK4 shells

## Status as of 2026-03-20

- Phase 0 refactor is complete in the macOS codebase.
- Task 1 completed: shared service contracts and `PlatformServices` are in place.
- Task 2 completed: macOS adapters now provide Apple translation and language-availability services through providers instead of direct `AppModel` ownership.
- Task 3 completed: `DictionaryEntry`, `LookupDirection`, `ParagraphTextStructure`, and OCR DTOs now live under `Shared/Domain`.
- Task 4 completed: offline SQLite dictionary storage is separated from the macOS system dictionary provider.
- Task 5 completed: repository landing zones for Windows, Linux, and `Native/core` are documented.
- Task 6 completed: App Store and Direct boundary files remain unchanged relative to `origin/main..HEAD`.
- Verification completed with `SnapTra Translator` and `SnapTra Translator Direct` Debug and Release builds.
- Remaining work is outside Phase 0: native Windows shell, native Linux shell, and any future shared `native/core` implementation are still pending.

---

### Task 1: Create shared service contracts and bootstrap container

**Files:**
- Create: `Shared/Services/PlatformServices.swift`
- Create: `Shared/Services/ServiceProtocols.swift`
- Modify: `SnapTra Translator/AppModel.swift`

**Step 1: Add protocol definitions**

Create explicit contracts for:

- `HotkeyControlling`
- `PermissionProviding`
- `ScreenCaptureProviding`
- `OCRProviding`
- `DictionaryProviding`
- `PrimaryTranslationProviding`
- `SentenceTranslationProviding`
- `SpeechProviding`
- `LanguageAvailabilityProviding`

Keep signatures close to existing macOS usage so adapters are thin.

**Step 2: Add `PlatformServices`**

Create a struct that bundles all protocol-conforming services needed by `AppModel`.

```swift
struct PlatformServices {
    let hotkey: HotkeyControlling
    let permissions: PermissionProviding
    let screenCapture: ScreenCaptureProviding
    let ocr: OCRProviding
    let dictionary: DictionaryProviding
    let primaryTranslation: PrimaryTranslationProviding
    let sentenceTranslation: SentenceTranslationProviding
    let speech: SpeechProviding
    let languageAvailability: LanguageAvailabilityProviding?
}
```

**Step 3: Update `AppModel` to accept services**

Modify the initializer so it can accept a `PlatformServices` value while still constructing the current macOS defaults when no explicit services are supplied.

**Step 4: Keep runtime behavior unchanged**

Do not change lookup flow, overlay flow, or settings behavior in this task. Only replace hard-coded construction with injected dependencies.

**Step 5: Verify build**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected:

- build succeeds
- no user-visible behavior changes

### Task 2: Add macOS adapters for existing implementations

**Files:**
- Create: `SnapTra Translator/MacPlatformServices.swift`
- Modify: `SnapTra Translator/HotkeyManager.swift`
- Modify: `SnapTra Translator/PermissionManager.swift`
- Modify: `SnapTra Translator/ScreenCaptureService.swift`
- Modify: `SnapTra Translator/OCRService.swift`
- Modify: `SnapTra Translator/DictionaryService.swift`
- Modify: `SnapTra Translator/TranslationService.swift`
- Modify: `SnapTra Translator/SentenceTranslationService.swift`
- Modify: `SnapTra Translator/SpeechService.swift`

**Step 1: Make existing services conform**

Add protocol conformances with minimal glue. Prefer extensions over rewriting implementations.

**Step 2: Add a macOS bootstrap factory**

Create a helper that returns `PlatformServices` backed by the current implementations.

```swift
enum MacPlatformServices {
    @MainActor
    static func make(settings: SettingsStore, permissions: PermissionManager) -> PlatformServices {
        PlatformServices(
            hotkey: HotkeyManager(),
            permissions: permissions,
            screenCapture: ScreenCaptureService(),
            ocr: OCRService(),
            dictionary: DictionaryService(),
            primaryTranslation: MacPrimaryTranslationProvider(),
            sentenceTranslation: SentenceTranslationService(),
            speech: SpeechService(),
            languageAvailability: MacLanguageAvailabilityProvider()
        )
    }
}
```

**Step 3: Wrap Apple translation**

Expose the existing `TranslationBridge` behavior through a dedicated macOS provider instead of letting `AppModel` own Apple translation details directly.

**Step 4: Verify both macOS schemes**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator Direct" -configuration Debug build
```

Expected:

- both builds succeed
- App Store and Direct target membership remains intact

### Task 3: Extract pure domain models and text helpers

**Files:**
- Create: `Shared/Domain/DictionaryEntry.swift`
- Create: `Shared/Domain/LookupDirection.swift`
- Create: `Shared/Domain/ParagraphTextStructure.swift`
- Create: `Shared/Domain/OCRModels.swift`
- Modify: `SnapTra Translator/DictionaryEntry.swift`
- Modify: `SnapTra Translator/LookupDirection.swift`
- Modify: `SnapTra Translator/ParagraphTextStructure.swift`
- Modify: `SnapTra Translator/OCRService.swift`
- Modify: `SnapTra Translator.xcodeproj/project.pbxproj`

**Step 1: Move one pure file at a time**

Start with `DictionaryEntry`, then `LookupDirection`, then `ParagraphTextStructure`, then OCR result DTOs.

**Step 2: Keep APIs source-compatible**

If existing imports or type names would break too many call sites, use typealiases or temporary forwarding wrappers to keep churn low.

**Step 3: Do not move Apple-only OCR invocation**

Only move the pure models and any pure post-processing helpers that compile without Apple OCR frameworks.

**Step 4: Run targeted tests**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -only-testing:SnapTra\ TranslatorTests/OCRParagraphGroupingTests test
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -only-testing:SnapTra\ TranslatorTests/LookupDirectionTests test
```

Expected:

- moved pure logic still passes current tests

### Task 4: Split local dictionary from macOS system dictionary behavior

**Files:**
- Create: `Shared/Services/OfflineDictionaryStore.swift`
- Create: `SnapTra Translator/MacSystemDictionaryProvider.swift`
- Modify: `SnapTra Translator/OfflineDictionaryService.swift`
- Modify: `SnapTra Translator/DictionaryService.swift`
- Modify: `SnapTra Translator/DictionaryDownloadManager.swift`

**Step 1: Rebrand the SQLite implementation as shared local storage**

Move the raw SQLite lookup logic into a shared local dictionary service with no `CoreServices` dependency.

**Step 2: Isolate system dictionary lookup**

Keep `DCSCopyTextDefinition` and HTML parsing behind a macOS-only provider.

**Step 3: Preserve current behavior ordering**

The current product behavior should remain:

- local ECDICT source available
- macOS system dictionary source available
- user-selected source ordering preserved

**Step 4: Verify dictionary paths**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -only-testing:SnapTra\ TranslatorTests/SmokeTests test
```

Expected:

- dictionary-backed smoke tests still pass
- manual dictionary download UI remains unchanged

### Task 5: Prepare repository landing zones for new platforms

**Files:**
- Create: `apps/windows/README.md`
- Create: `apps/linux/README.md`
- Create: `Native/core/README.md`
- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `README.zh-CN.md`

**Step 1: Add platform placeholders**

Document intended stacks and scope:

- Windows: WinUI 3 + Win32 integration
- Linux: GTK4/libadwaita, GNOME/Wayland first
- Native core: deferred, for proven pure logic only

**Step 2: Document architecture boundary**

Update repo docs so future work does not accidentally place Windows/Linux shell code into the macOS target.

**Step 3: Do not add platform build systems yet**

This task is documentation-only. Avoid introducing incomplete Windows/Linux project files before the service boundary lands cleanly.

### Task 6: Validate App Store safety and project stability

**Files:**
- Verify only

**Step 1: Confirm App Store entitlements are unchanged**

Inspect:

- `SnapTra Translator/SnapTra AppStore.entitlements`
- `SnapTra Translator/Info-AppStore.plist`

Expected:

- no new entitlements
- no new helper/runtime requirements

**Step 2: Confirm direct build entitlements remain channel-specific**

Inspect:

- `SnapTra Translator/SnapTra Direct.entitlements`

Expected:

- Sparkle-related exceptions remain direct-only

**Step 3: Run release builds**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Release build
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator Direct" -configuration Release build
```

Expected:

- both release builds succeed
- App Store build contents remain materially unchanged apart from structural source refactoring

### Task 7: Start Windows v1 implementation in isolation

**Files:**
- Create: `apps/windows/<project files>`
- Reference: `Shared/Services/*`
- Reference: `Shared/Domain/*`

**Step 1: Build the shell first**

Implement only:

- tray bootstrap
- hotkey capture
- settings shell

**Step 2: Add OCR lookup flow**

Wire Windows-native capture and OCR into the shared request/response shapes before attempting full paragraph mode.

**Step 3: Add overlay and dictionary**

Reuse the shared local dictionary format and the same orchestration semantics defined by the service contracts.

**Step 4: Keep macOS untouched during this task**

Do not modify App Store or direct-distribution targets while the first Windows shell is coming up.
