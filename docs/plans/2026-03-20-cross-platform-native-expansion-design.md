# Cross-Platform Native Expansion Design

**Goal:** Add Windows and Linux versions without destabilizing the existing macOS App Store product, while preserving the current macOS feature set and keeping each desktop build as native and lightweight as practical.

## Status as of 2026-03-20

- The Phase 0 macOS refactor described in this document is complete.
- `AppModel` now depends on injected platform services instead of directly owning Apple translation and language-pack managers.
- Shared domain code now contains the moved pure models and OCR DTOs needed for future platform shells.
- Offline dictionary storage and the macOS system dictionary adapter are now separated.
- App Store and Direct entitlement boundaries remain unchanged, and both schemes pass Debug and Release builds.
- Windows and Linux shells described below have not been implemented yet.
- `Native/core` remains a placeholder directory and has not been linked into the macOS targets.

## Problem

- The current app is a macOS-first codebase that directly binds product logic to Apple-only frameworks such as `AppKit`, `ScreenCaptureKit`, `Vision`, `Translation`, and `CoreServices`.
- The current app has already shipped through the Mac App Store with screen capture, offline dictionary download, third-party translation, and third-party TTS, so a cross-platform refactor must not materially change the reviewed macOS feature boundary.
- Windows and Linux need equivalent product flows, but their native desktop integration points differ significantly for tray behavior, hotkeys, permissions, capture, OCR, and overlays.
- A direct rewrite into one cross-platform UI stack would dilute native behavior and likely increase binary size, memory use, and maintenance drag.
- Pulling a new Rust or C++ engine directly into the Mac App Store target would increase build, signing, and review surface area before it provides concrete value.

## Product Decisions

### Scope

- Keep the existing macOS App Store and direct-distribution builds functional and behaviorally stable.
- Expand to Windows first, then Linux.
- Treat Windows/Linux v1 as: local OCR, local dictionary, existing network-backed translation and TTS providers, native tray and overlay behavior.
- Defer offline translation engines to a later phase.
- Keep the current macOS feature set, including offline dictionary download and third-party services.

### Non-Goals

- Do not replace the current macOS UI shell.
- Do not migrate the macOS App Store target to a shared Rust/C++ core in the first phase.
- Do not attempt a single shared cross-platform UI toolkit for macOS, Windows, and Linux.
- Do not promise identical Linux behavior across every desktop environment in v1.
- Do not redesign the current App Store entitlement or update-channel split beyond what already exists.

## Current-State Constraints

### Tight macOS Coupling

- `AppModel` currently constructs concrete macOS services directly:
  - `HotkeyManager`
  - `ScreenCaptureService`
  - `OCRService`
  - `DictionaryService`
  - `SpeechService`
  - `SentenceTranslationService`
  - `TranslationBridge`
- Overlay presentation is implemented as AppKit window controllers and `NSHostingView` panels.
- Permissions are represented as macOS-specific screen-recording checks and settings deep links.

### Existing Distribution Shape

- The repository already separates App Store and direct distribution through distinct plist and entitlement files.
- The direct build carries additional Sparkle-specific sandbox configuration.
- The App Store build already includes network access and the current user-facing feature set; the cross-platform refactor should preserve that reviewed shape rather than reopen it unnecessarily.

### Reusable Assets Already Present

- The offline dictionary storage format is SQLite-backed and not inherently macOS-only.
- Several data models and text-structure helpers are already platform-agnostic in spirit, even if they still live inside the macOS target.
- The product flow itself is stable: trigger -> capture -> OCR -> selection -> dictionary/translation/TTS -> overlay.

## Recommended Architecture

### 1. Stable macOS Shell, Shared Domain Boundary

Preserve the current macOS target structure as the stable product shell, and introduce a narrow shared domain layer that contains only:

- product data models
- text-structure logic
- dictionary record models
- service protocols
- request and response DTOs

This layer should stay free of `AppKit`, `SwiftUI`, `Vision`, `Translation`, `ScreenCaptureKit`, and any Windows/Linux-specific APIs.

### 2. Invert `AppModel` Dependencies, Not `AppModel` Ownership

Do not replace `AppModel`. Instead, stop hard-coding concrete service construction inside it.

Introduce a `PlatformServices` container that supplies protocol-based implementations for:

- hotkey control
- permissions
- screen capture
- OCR
- dictionary lookup
- primary translation
- sentence translation
- speech
- language availability

The default macOS app path still constructs the current macOS implementations, so the functional behavior of the shipped app remains unchanged.

### 3. Extract Shared Logic Incrementally

First extract only the parts that are clearly platform-agnostic:

- `DictionaryEntry`
- lookup-direction and language-pair models
- paragraph text reconstruction
- OCR result DTOs
- offline dictionary SQLite access
- selection and normalization helpers that do not require Apple frameworks

Leave the macOS system dictionary adapter, Apple OCR invocation, Apple translation bridge, AppKit windowing, and permissions in the macOS target.

### 4. Keep Platform Shells Native

#### macOS

- Keep `SwiftUI + AppKit`.
- Keep the current two-target distribution split.
- Keep current App Store functionality and service surface.

#### Windows

- Use a native Windows shell: WinUI 3 for settings and standard UI, plus lightweight Win32 integration for tray and message-loop responsibilities.
- Implement native capture, hotkeys, overlays, and OCR using Windows platform APIs where practical.
- Reuse the same dictionary format and product flow.

#### Linux

- Use a native Linux shell oriented around GTK4 and libadwaita.
- Scope v1 to GNOME/Wayland first.
- Use desktop portals for capture, permissions, and shortcuts wherever required.
- Reuse the same dictionary format and product flow.

### 5. Delay Shared Native Core Until It Earns Its Keep

Add a future `native/core` area for Rust or C++ only after Windows v1 proves which logic is truly stable and worth sharing.

The first candidates for a shared native core are:

- dictionary lookup over SQLite
- text normalization
- OCR post-processing
- paragraph grouping and selection helpers
- config parsing

The following should remain platform-local:

- tray/menu integration
- hotkeys
- permissions
- capture sessions
- overlay windows
- native translation/TTS bridges
- updater/distribution plumbing

## Repository Shape

### Phase-1 Shape

Use the existing Xcode project as the source of truth for macOS and add repository-level separation without forcing a full move on day one:

```text
SnapTra Translator/
├─ SnapTra Translator/                # existing macOS app target files
├─ Shared/
│  ├─ Domain/
│  └─ Services/
├─ apps/
│  ├─ windows/
│  └─ linux/
└─ Native/
   └─ core/
```

This keeps file churn low inside the current macOS target while creating clear landing zones for new platform code.

### Future Shape

After the protocol boundary is stable, the shared Swift domain code can be moved into a local Swift Package without changing the architecture.

## File-Level Refactor Strategy

### Files To Keep As macOS Shell

- `Snap_TranslateApp.swift`
- `OverlayWindowController.swift`
- `OverlayView.swift`
- `SettingsWindowView.swift`
- `DictionarySettingsView.swift`
- `AboutSettingsView.swift`
- `HotkeyManager.swift`
- `PermissionManager.swift`
- `UpdateChecker.swift` split structure

These files are either AppKit shell, macOS-specific integration, or already part of the reviewed distribution boundary.

### Files To Split Or Reclassify

- `AppModel.swift`
  - keep the orchestration logic
  - replace direct service construction with injected dependencies
- `DictionaryService.swift`
  - split local SQLite logic from macOS system dictionary logic
- `OCRService.swift`
  - keep Vision invocation local
  - move result DTOs and pure post-processing where practical
- `TranslationService.swift`
  - keep Apple translation bridge macOS-only
- `OfflineDictionaryService.swift`
  - prepare as a shared local-dictionary implementation

### Shared Interfaces To Introduce

- `HotkeyControlling`
- `PermissionProviding`
- `ScreenCaptureProviding`
- `OCRProviding`
- `DictionaryProviding`
- `PrimaryTranslationProviding`
- `SentenceTranslationProviding`
- `SpeechProviding`
- `LanguageAvailabilityProviding`

### Bootstrap Container

Introduce a `PlatformServices` value that the macOS app constructs with current implementations:

- `MacHotkeyManagerAdapter`
- `MacPermissionProvider`
- `MacScreenCaptureProvider`
- `MacOCRProvider`
- `MacDictionaryProvider`
- `MacPrimaryTranslationProvider`
- `MacSentenceTranslationProvider`
- `MacSpeechProvider`
- `MacLanguageAvailabilityProvider`

This preserves behavior while creating the exact seam Windows and Linux need later.

## Windows v1 Design

### Functional Scope

- Tray app
- Global hotkey
- Local region capture around cursor
- OCR for hovered text
- Paragraph mode
- Floating overlay
- Offline SQLite dictionary
- Existing network-backed translation and TTS sources

### Native Shape

- WinUI 3 settings window
- Win32 interop layer for tray icon and hotkey message handling
- Native topmost transparent overlay window
- Windows capture pipeline
- Windows OCR pipeline with a compatibility fallback if needed per device support

### Why This Fits The Shared Boundary

Windows needs the same orchestration semantics as macOS, but not the same shell APIs. Protocol injection allows Windows to adopt the product flow without inheriting AppKit assumptions.

## Linux v1 Design

### Functional Scope

- Tray or status integration where supported
- Configurable shortcut flow
- Screen capture through portal-compatible paths
- OCR with Tesseract
- Overlay result window
- Offline SQLite dictionary
- Existing network-backed translation and TTS sources

### Scope Guardrails

- Prioritize GNOME/Wayland first.
- Expect desktop-environment-specific compromises.
- Keep Linux delivery behind Windows so platform assumptions can be validated first.

## Mac App Store Impact

### Guardrails

- Do not remove existing reviewed functionality.
- Do not add new executable download or plugin systems to the App Store target.
- Do not add new helper binaries, interpreters, or embedded runtimes solely for cross-platform reuse.
- Do not route the App Store target through the future native core in phase 1.

### Why This Is Safe

- The macOS target continues to ship the same product shell and the same existing entitlement boundary.
- The first refactor is structural, not behavioral.
- New Windows/Linux work lands in separate directories and future targets, instead of widening the App Store binary unnecessarily.

## Rollout Plan

### Phase 0

- Completed on 2026-03-20
- Introduced protocols and `PlatformServices`
- Kept default macOS behavior identical
- Reclassified shared models and pure helpers

### Phase 1

- Build Windows v1 shell on top of the new protocol boundary

### Phase 2

- Extract proven pure logic into `native/core` only if duplication becomes costly

### Phase 3

- Build Linux v1 with GTK/libadwaita and portal-first integration

## Success Criteria

- macOS App Store and direct builds continue to behave as they do today.
- `AppModel` no longer hard-codes macOS service construction.
- Shared code is limited to genuinely platform-agnostic logic.
- Windows v1 can implement the product flow without copying macOS shell code.
- Linux v1 has a clear, scoped path that does not force a non-native UI compromise.
