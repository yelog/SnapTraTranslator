# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

### Building
```bash
# Debug build
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build

# Release build
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Release build

# Clean
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" clean
```

### Running
Open the project in Xcode:
```bash
open "SnapTra Translator.xcodeproj"
```
Then run the "SnapTra Translator" scheme (⌘R).

### Testing
No test target currently exists in this project.

## Project Architecture

### App Structure
**SnapTra Translator** is a macOS menu bar app (accessory app) that provides instant translation via OCR. The app runs as a status item (menu bar icon) and shows windows only when needed.

### Core Flow
1. User presses configured hotkey (modifier key like Shift, Control, Option, Command, or Fn)
2. App captures screen region around cursor (`ScreenCaptureService`)
3. OCR extracts words from capture (`OCRService` using Vision framework)
4. Word closest to cursor is selected (distance-based algorithm)
5. Translation happens via macOS 15 Translation framework (`TranslationBridge`)
6. Dictionary lookup provides definitions and phonetics (`DictionaryService`)
7. Results show in floating overlay bubble near cursor (`OverlayWindowController`)
8. Release hotkey to dismiss (or click to dismiss if continuous mode is off)

**Screen Configuration Changes**: On display changes (`NSApplication.didChangeScreenParametersNotification`), `AppModel.handleScreenConfigurationChange()` cancels any active lookup and invalidates the `ScreenCaptureService` cache.

### Key Components

#### AppDelegate Pattern
- `Snap_TranslateApp`: Main app entry point with `@NSApplicationDelegateAdaptor`
- `AppDelegate`: Manages status item, windows, permissions, and entitlements
- App runs as `.accessory` activation policy (no dock icon by default)
- Three window controllers: Settings, Paywall, and invisible Translation service window

#### AppModel (Central Controller)
The `AppModel` class is the heart of the app, orchestrating all services:
- Manages hotkey press/release lifecycle
- Coordinates OCR → Translation → Dictionary pipeline
- Handles overlay state machine (`OverlayState` enum)
- Debounces mouse movement for continuous translation mode
- Manages multiple concurrent tasks with cancellation

**Important**: `AppModel` uses `activeLookupID: UUID?` to ensure only the latest lookup completes. Always check if `activeLookupID == lookupID` before updating state.

**Definition Translation**: Dictionary definitions are translated in parallel using `withTaskGroup` for performance. Each definition's `meaning` is translated separately, with special handling:
- For Chinese targets: Keeps existing dictionary translation if available
- For English targets: Filters definitions to only those with English content (regex check for `[a-zA-Z]{3,}`)
- Same-language pairs: Uses original meaning without translation

#### Translation Architecture (macOS 15+)
**Critical**: The Translation API requires a SwiftUI view hierarchy with `.translationTask()` modifier.

- `TranslationBridge`: Actor-free bridge using async streams
- `TranslationBridgeView`: Invisible 1x1 window hosting the translation session
- `TranslationServiceWindowHolder`: Singleton holding the invisible window
- Window must remain alive throughout app lifecycle or translation fails
- Stream-based request/response pattern with continuation-based timeout

Language changes require full session restart: cancel pending requests → reset stream → recreate configuration → force view ID change.

#### OCR Word Detection
`OCRService` uses Vision framework with custom tokenization:
- Splits on CamelCase boundaries (e.g., "getUserName" → "get", "User", "Name")
- Calculates word bounding boxes using character ratio (most stable method)
- Filters to English letters only for token boundaries (numbers/symbols are delimiters)
- Returns `RecognizedWord` array with normalized bounding boxes

**Word Selection Algorithm**: Finds all words containing cursor point (with tolerance), then selects the one with closest center-to-cursor distance.

#### Hotkey Management
- `HotkeyManager`: Registers global event monitor for single-key hotkeys
- `HotkeyUtilities`: Maps virtual key codes to display names
- Supports modifier keys: Shift (left/right), Control (left/right), Option (left/right), Command (left/right), Fn
- Callbacks: `onTrigger` (key down) and `onRelease` (key up)

#### Window Architecture
Three window controllers exist:
1. **SettingsWindowController**: Shows settings UI (ContentView), 360x640
2. **PaywallWindowController**: Shows purchase UI (PaywallView), 400x520
3. **TranslationServiceWindowHolder**: Invisible 1x1 borderless window for translation session

**OverlayWindowController**: Floating panel showing translation results
- Positioned near cursor via `show(at: CGPoint)`
- Can be interactive (clickable/draggable) or non-interactive
- Uses `OverlayView` with SwiftUI content

**DebugOverlayWindowController**: Red overlay showing OCR capture region (debug mode only)

#### Continuous Translation Mode
When enabled (`settings.continuousTranslation`):
- Mouse move events trigger new lookups while hotkey is pressed
- Debounced by 100ms to reduce OCR overhead
- Position threshold of 10pt prevents identical captures
- Overlay remains visible and updates in place

When disabled:
- Single lookup on hotkey press
- Overlay becomes interactive (clickable to dismiss or speaker button)
- Mouse movement ignored

#### Translation Service Warmup
On macOS 15+, `warmupServices()` performs a dummy translation at launch ("hello") to initialize the Translation framework. This prevents first-translation delays but means the app briefly activates translation services on startup.

#### Entitlement System (Currently Disabled)
The entitlement system was designed but is currently not active in the codebase. The `EntitlementManager`, `StoreKitManager`, and paywall UI (`PaywallView.swift`) exist but are not integrated into the main flow. Debug builds bypass all checks.

#### Settings Persistence
`SettingsStore`: ObservableObject with `@AppStorage` properties
- Source/target languages (Locale.Language identifiers)
- Single-key hotkey
- Boolean flags: playPronunciation, continuousTranslation, launchAtLogin, debugShowOcrRegion

All settings auto-persist to UserDefaults. Changes trigger side effects via Combine in `AppModel.bindSettings()`.

#### Permission Management
`PermissionManager`: Monitors and requests macOS permissions
- Screen Recording: Required for OCR capture
- Published status object with boolean flags
- `requestAndOpenScreenRecording()`: Shows system settings

App detects permission grant after restart via UserDefaults comparison and auto-shows settings window.

#### Language Pack Handling (macOS 15+)
`LanguagePackManager`: Checks Translation framework language availability
- Three states: `.installed`, `.supported` (downloadable), `.unsupported`
- Caches status to avoid repeated checks
- `checkLanguagePair()`: Performs check and shows alert if needed
- `openTranslationSettings()`: Deep links to System Settings > Translation

Settings UI shows status icon (green checkmark / red X) for selected language pair.

**Language Status Caching**: `AppModel` caches the last language pair availability check in `cachedLanguageStatus` to avoid redundant system calls during rapid lookups.

### State Management Patterns

#### Combine Publishers
Heavy use of Combine for reactive updates:
- Settings changes → Hotkey restart, lookup cancellation
- Permission changes → Hotkey enable/disable
- Language changes → Translation session reset, availability check
- Entitlement changes → Paywall dismissal

#### Task Cancellation
Critical for responsiveness:
- `lookupTask?.cancel()` before starting new lookup
- Check `Task.isCancelled` and `activeLookupID` at each async boundary
- Translation timeout via race between translate and sleep tasks

#### Window Visibility Logic
Complex logic in `AppDelegate.updateVisibilityFromCurrentState()`:
- If missing Screen Recording → show settings
- If language pack not installed → show settings
- If user manually opened settings → keep visible
- Otherwise → hide dock icon (accessory mode)

Special case: After permission grant (detected on restart), force-show settings window once.

### macOS Version Compatibility

The app requires macOS 14+ but translation features require macOS 15+:
- Use `if #available(macOS 15.0, *)` guards around Translation API
- `LanguagePackManager` only initialized on macOS 15+
- Stored as `Any?` and cast when needed to avoid compilation errors on older SDKs
- TranslationBridgeView and related components are `@available(macOS 15.0, *)`

### Code Style

See `AGENTS.md` for comprehensive style guidelines. Key conventions:
- Indentation: 4 spaces
- Trailing commas in multiline collections
- `@MainActor` on classes that touch UI state
- Avoid force unwraps; use `guard`/`if let`
- Keep SwiftUI `body` small; extract subviews
- Use `@State` for view-local state, `@StateObject` for owned models, `@ObservedObject` for injected models
- Localized strings: Use `String(localized: "key")` (stored in `Localizable.xcstrings`)

### Common Gotchas

1. **Translation hangs**: Ensure TranslationServiceWindowHolder.shared.window stays alive
2. **Language change breaks translation**: Must reset entire session (see `TranslationBridgeView.resetConfiguration()`)
3. **OCR misses words**: Check language is set correctly in VNRecognizeTextRequest
4. **Hotkey doesn't work**: Screen Recording permission required for event monitoring
5. **Overlay clipped at screen edge**: Normal behavior, debug overlay shows actual capture rect
6. **Trial/license bypass in debug**: `bypassLicenseCheck` always returns true in Debug builds

### Dependencies

All frameworks are system frameworks (no external dependencies):
- SwiftUI (UI)
- Translation (macOS 15+ translation)
- Vision (OCR)
- AppKit (windows, status item, permissions)
- AVFoundation (text-to-speech via `SpeechService`)
- StoreKit (in-app purchases)
- Combine (reactive state)

### File Organization

```
SnapTra Translator/
├── Snap_TranslateApp.swift          # App entry + AppDelegate + window controllers
├── AppModel.swift                   # Central controller/coordinator
├── ContentView.swift                # Settings UI (main container)
├── SettingsView.swift               # Language/hotkey pickers
├── PaywallView.swift                # Purchase UI (not currently active)
├── OverlayView.swift                # Translation result bubble UI
├── OverlayWindowController.swift    # Floating overlay window
├── TranslationService.swift         # TranslationBridge + TranslationBridgeView
├── OCRService.swift                 # Vision-based word recognition
├── ScreenCaptureService.swift       # Screen capture around cursor
├── DictionaryService.swift          # System dictionary lookups
├── DictionaryEntry.swift            # Dictionary models
├── PhoneticService.swift            # Phonetic notation
├── SpeechService.swift              # Text-to-speech
├── HotkeyManager.swift              # Global hotkey registration
├── HotkeyUtilities.swift            # Key code mapping
├── PermissionManager.swift          # Permission checking
├── LanguagePackManager.swift        # Translation language availability
├── SettingsStore.swift              # @AppStorage settings
├── AppSettings.swift                # UserDefaults keys
├── LoginItemManager.swift           # Launch at login
└── Localizable.xcstrings            # String catalog for i18n (English, Chinese, Japanese, Korean)
```

### Debugging

Enable "Debug OCR Region" in settings to visualize:
- Red rectangle: Screen capture area
- Green boxes: Detected word bounding boxes
- Useful for troubleshooting word selection and OCR accuracy
