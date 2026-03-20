# Cross-Platform Native Expansion Phase 0 Closeout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Finish the remaining Phase 0 refactor work so the macOS app keeps current behavior while the codebase exposes complete platform seams for future Windows and Linux shells.

**Architecture:** Keep the shipping macOS shell intact and close the remaining abstraction gaps instead of rewriting the app. The missing work is concentrated in two areas: wrapping Apple translation and language-pack availability behind providers, and moving genuinely platform-agnostic models out of the macOS shell area into `Shared/Domain`.

**Tech Stack:** Swift, SwiftUI, AppKit, Translation, Vision, SQLite3, Xcode filesystem-synchronized groups, future WinUI 3 / GTK4 shells

---

> **Current constraint:** The repository still has no test target. Use build verification and tight smoke checks for this phase instead of inventing partial XCTest scaffolding.

### Task 1: Add the missing primary translation and language-availability contracts

**Files:**
- Modify: `SnapTra Translator/Shared/Services/ServiceProtocols.swift`
- Modify: `SnapTra Translator/Shared/Services/PlatformServices.swift`
- Create: `SnapTra Translator/Shared/Domain/LanguageAvailabilityStatus.swift`
- Create: `SnapTra Translator/MacPrimaryTranslationProvider.swift`
- Create: `SnapTra Translator/MacLanguageAvailabilityProvider.swift`
- Modify: `SnapTra Translator/MacPlatformServices.swift`

**Step 1: Add platform-neutral language-availability types**

Create a small shared type that does not leak `Translation` framework symbols outside the macOS shell.

```swift
enum LanguageAvailabilityStatus: Equatable {
    case unknown
    case unsupported
    case supported
    case installed
}
```

**Step 2: Extend service contracts**

Add the missing contracts to `ServiceProtocols.swift`.

```swift
protocol PrimaryTranslationProviding: AnyObject {
    func translate(
        text: String,
        sourceLanguage: String?,
        targetLanguage: String,
        timeout: TimeInterval
    ) async throws -> String

    func translateBatch(
        texts: [String],
        sourceLanguage: String?,
        targetLanguage: String,
        timeout: TimeInterval
    ) async throws -> [String]

    func cancelAllPendingRequests()
}

@MainActor
protocol LanguageAvailabilityProviding: AnyObject {
    var isChecking: Bool { get }
    func checkLanguagePair(from sourceLanguage: String, to targetLanguage: String) async -> LanguageAvailabilityStatus
    func checkLanguagePairQuiet(from sourceLanguage: String, to targetLanguage: String) async -> LanguageAvailabilityStatus
    func getStatus(from sourceLanguage: String, to targetLanguage: String) -> LanguageAvailabilityStatus?
    func openTranslationSettings()
}
```

**Step 3: Extend `PlatformServices`**

Add the missing provider slots.

```swift
struct PlatformServices {
    let hotkey: any HotkeyControlling
    let permissions: any PermissionProviding
    let screenCapture: any ScreenCaptureProviding
    let ocr: any OCRProviding
    let dictionary: any DictionaryProviding
    let primaryTranslation: any PrimaryTranslationProviding
    let sentenceTranslation: any SentenceTranslationProviding
    let speech: any SpeechProviding
    let languageAvailability: (any LanguageAvailabilityProviding)?
}
```

**Step 4: Add macOS adapters**

Wrap existing Apple implementations instead of moving product logic.

```swift
@MainActor
final class MacPrimaryTranslationProvider: PrimaryTranslationProviding {
    let bridge = TranslationBridge()
    // map string identifiers to Locale.Language and forward to bridge
}
```

```swift
@available(macOS 15.0, *)
@MainActor
final class MacLanguageAvailabilityProvider: ObservableObject, LanguageAvailabilityProviding {
    private let manager = LanguagePackManager()
    // map LanguageAvailability.Status <-> LanguageAvailabilityStatus
}
```

**Step 5: Wire the new adapters into `MacPlatformServices`**

Keep the default macOS bootstrap path intact.

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected:
- build succeeds
- no target membership edits outside files under `SnapTra Translator/`

**Step 6: Commit**

```bash
git add "SnapTra Translator/Shared/Services/ServiceProtocols.swift" \
        "SnapTra Translator/Shared/Services/PlatformServices.swift" \
        "SnapTra Translator/Shared/Domain/LanguageAvailabilityStatus.swift" \
        "SnapTra Translator/MacPrimaryTranslationProvider.swift" \
        "SnapTra Translator/MacLanguageAvailabilityProvider.swift" \
        "SnapTra Translator/MacPlatformServices.swift"
git commit -m "refactor: add translation and language availability providers"
```

### Task 2: Remove `AppModel` ownership of Apple translation and language-pack managers

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`
- Modify: `SnapTra Translator/Snap_TranslateApp.swift`
- Modify: `SnapTra Translator/SettingsWindowView.swift`
- Modify: `SnapTra Translator/TranslationService.swift`
- Create: `SnapTra Translator/MacTranslationServiceHost.swift`

**Step 1: Replace concrete `TranslationBridge` ownership in `AppModel`**

Change `AppModel` to depend on `PrimaryTranslationProviding` and optional `LanguageAvailabilityProviding`.

```swift
let primaryTranslation: any PrimaryTranslationProviding
let languageAvailability: (any LanguageAvailabilityProviding)?
```

Remove:

```swift
let translationBridge: TranslationBridge
private var _languagePackManager: Any?
```

**Step 2: Forward existing translation call sites through the provider**

Update all current translation paths in `AppModel`:
- single word pretranslation
- paragraph translation
- dictionary meaning translation
- request cancellation

Use:

```swift
try await primaryTranslation.translate(...)
try await primaryTranslation.translateBatch(...)
primaryTranslation.cancelAllPendingRequests()
```

**Step 3: Move hidden translation window hosting out of `AppModel`**

Keep `TranslationBridgeView` and Apple UI hosting as macOS-only plumbing.

Create a small host helper that only knows how to host `MacPrimaryTranslationProvider.bridge`:

```swift
@available(macOS 15.0, *)
enum MacTranslationServiceHost {
    static func installIfNeeded(for provider: MacPrimaryTranslationProvider) { ... }
    static func warmupIfNeeded(provider: MacPrimaryTranslationProvider, sourceLanguage: String, targetLanguage: String) { ... }
}
```

Update `Snap_TranslateApp.swift` to use the host helper only when the injected provider is the macOS implementation.

**Step 4: Replace UI references to `model.languagePackManager`**

Update `SettingsWindowView.swift` to read from `model.languageAvailability` instead of the concrete manager:

```swift
model.languageAvailability?.getStatus(...)
await model.languageAvailability?.checkLanguagePair(...)
model.languageAvailability?.openTranslationSettings()
```

**Step 5: Verify both macOS schemes**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator Direct" -configuration Debug build
```

Expected:
- both builds succeed
- settings window still compiles against the abstract provider
- hidden translation bridge host remains macOS-only

**Step 6: Commit**

```bash
git add "SnapTra Translator/AppModel.swift" \
        "SnapTra Translator/Snap_TranslateApp.swift" \
        "SnapTra Translator/SettingsWindowView.swift" \
        "SnapTra Translator/TranslationService.swift" \
        "SnapTra Translator/MacTranslationServiceHost.swift"
git commit -m "refactor: decouple app model from apple translation services"
```

### Task 3: Establish `Shared/Domain` and move the easiest pure models first

**Files:**
- Create: `SnapTra Translator/Shared/Domain/DictionaryEntry.swift`
- Create: `SnapTra Translator/Shared/Domain/LookupDirection.swift`
- Create: `SnapTra Translator/Shared/Domain/ParagraphTextStructure.swift`
- Modify: `SnapTra Translator/DictionaryEntry.swift`
- Modify: `SnapTra Translator/LookupDirection.swift`
- Modify: `SnapTra Translator/ParagraphTextStructure.swift`
- Create: `SnapTra Translator/ParagraphTextAttributedStringBuilder.swift`

**Step 1: Move `DictionaryEntry` into `Shared/Domain`**

Copy the full model into `Shared/Domain/DictionaryEntry.swift`.

Replace the old shell file with a forwarding typealias or remove it if the synchronized group picks up the new file cleanly and all call sites compile.

Preferred minimal wrapper:

```swift
typealias DictionaryEntry = SharedDictionaryEntry
```

Only use a wrapper if a direct move causes too much churn.

**Step 2: Move `LookupDirection` into `Shared/Domain`**

Apply the same strategy: real type in `Shared/Domain`, compatibility shim only if needed.

**Step 3: Split `ParagraphTextStructure` from AppKit-only attributed-string code**

Move the pure block parsing and translation-application logic into `Shared/Domain/ParagraphTextStructure.swift`.

Create a new macOS-only file for attributed-string rendering:

```swift
struct ParagraphTextAttributedStringBuilder {
    static func build(...) -> NSAttributedString { ... }
}
```

This removes `AppKit` from the shared paragraph structure.

**Step 4: Verify current call sites compile unchanged**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected:
- no manual `project.pbxproj` edits needed because files live under the synchronized root
- paragraph rendering still works through the new macOS-only builder

**Step 5: Commit**

```bash
git add "SnapTra Translator/Shared/Domain/DictionaryEntry.swift" \
        "SnapTra Translator/Shared/Domain/LookupDirection.swift" \
        "SnapTra Translator/Shared/Domain/ParagraphTextStructure.swift" \
        "SnapTra Translator/DictionaryEntry.swift" \
        "SnapTra Translator/LookupDirection.swift" \
        "SnapTra Translator/ParagraphTextStructure.swift" \
        "SnapTra Translator/ParagraphTextAttributedStringBuilder.swift"
git commit -m "refactor: move pure domain models into shared domain"
```

### Task 4: Extract OCR DTOs and pure OCR post-processing

**Files:**
- Create: `SnapTra Translator/Shared/Domain/OCRModels.swift`
- Modify: `SnapTra Translator/OCRService.swift`
- Modify: `SnapTra Translator/ParagraphTextStructure.swift`
- Modify: `SnapTra Translator/AppModel.swift`

**Step 1: Move OCR DTOs out of `OCRService.swift`**

Create `Shared/Domain/OCRModels.swift` with:

```swift
struct RecognizedWord: Equatable { ... }
struct RecognizedTextLine: Equatable { ... }
struct RecognizedParagraph: Equatable { ... }
```

**Step 2: Leave Vision invocation in `OCRService.swift`**

Only remove the DTO declarations and keep:
- `VNRecognizeTextRequest`
- observation conversion
- image-recognition execution

**Step 3: Extract pure grouping helpers only if they compile without Vision**

If paragraph grouping helpers can compile with only Foundation/CoreGraphics, keep them with shared models. If not, postpone the helper move and move only the DTOs in this task.

**Step 4: Verify both schemes**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator Direct" -configuration Debug build
```

Expected:
- both builds succeed
- OCR result types are no longer owned by `OCRService.swift`

**Step 5: Commit**

```bash
git add "SnapTra Translator/Shared/Domain/OCRModels.swift" \
        "SnapTra Translator/OCRService.swift" \
        "SnapTra Translator/ParagraphTextStructure.swift" \
        "SnapTra Translator/AppModel.swift"
git commit -m "refactor: move ocr models into shared domain"
```

### Task 5: Close out Phase 0 verification and document remaining work

**Files:**
- Modify: `docs/plans/2026-03-20-cross-platform-native-expansion-plan.md`
- Modify: `docs/plans/2026-03-20-cross-platform-native-expansion-design.md`
- Verify only: `SnapTra Translator/SnapTra AppStore.entitlements`
- Verify only: `SnapTra Translator/Info-AppStore.plist`
- Verify only: `SnapTra Translator/SnapTra Direct.entitlements`

**Step 1: Verify App Store boundary files remain unchanged**

Run:

```bash
git diff --name-only origin/main..HEAD -- \
  "SnapTra Translator/SnapTra AppStore.entitlements" \
  "SnapTra Translator/Info-AppStore.plist" \
  "SnapTra Translator/SnapTra Direct.entitlements"
```

Expected:
- no output

**Step 2: Verify both current macOS schemes**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Release build
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator Direct" -configuration Release build
```

Expected:
- both release builds succeed

**Step 3: Update the plan and design docs with actual completion status**

Mark:
- Task 1: completed
- Task 2: completed
- Task 3: completed
- Task 4: completed
- Windows/Linux shell work: still pending
- `native/core`: still placeholder only

**Step 4: Commit**

```bash
git add "docs/plans/2026-03-20-cross-platform-native-expansion-plan.md" \
        "docs/plans/2026-03-20-cross-platform-native-expansion-design.md"
git commit -m "docs: update cross-platform phase0 completion status"
```
