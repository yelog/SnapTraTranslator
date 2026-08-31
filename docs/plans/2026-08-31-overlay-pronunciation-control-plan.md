# Overlay Pronunciation Control Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a compact pronunciation and auto-play control to word and sentence overlays, with reliable loading, playing, replay, completion, failure, and cancellation feedback.

**Architecture:** Extend `SpeechService` with a generation-safe observable playback lifecycle backed by real AVFoundation delegate callbacks. Route both existing automatic speech and new manual replay through context-aware `AppModel` helpers, then render one reusable two-zone SwiftUI capsule in the word and sentence headers. Reuse the existing persisted word and sentence auto-play settings without adding another preference.

**Tech Stack:** Swift 6, SwiftUI, Combine, AVFoundation, XCTest, xcodebuild

---

### Task 1: Define and test the speech playback lifecycle

**Files:**
- Modify: `SnapTra Translator/SpeechService.swift:17-28, 61-125, 127-376`
- Test: `SnapTra TranslatorTests/SpeechServiceTests.swift:278-442, 503-590`

**Step 1: Write failing lifecycle tests**

Add focused tests to `SpeechServiceTests` for these transitions:

```swift
func testOnlineSpeechTransitionsFromLoadingToPlayingToIdle() async
func testAppleSpeechTransitionsFromPlayingToIdle() async
func testStopSpeakingReturnsStateToIdle() async
func testPlaybackFailurePublishesFailedState() async
func testStaleCompletionCannotResetReplacementPlayback() async
```

Use the existing `ControlledTTSFetcher` and extend `SpeechAudioOutputSpy` with controlled start, finish, and failure callbacks. Assert exact state transitions rather than only checking that an output method was called.

**Step 2: Run the tests and verify they fail**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test \
  -only-testing:SnapTra_TranslatorTests/SpeechServiceTests
```

Expected: the new tests fail because `SpeechService` does not expose playback state or natural-completion callbacks.

**Step 3: Add the minimal public state model**

In `SpeechService.swift`, add an equatable state carrying the current request identifier:

```swift
enum SpeechPlaybackState: Equatable {
    case idle
    case loading(requestID: UUID)
    case playing(requestID: UUID)
    case failed(requestID: UUID)

    var requestID: UUID? {
        switch self {
        case .idle:
            nil
        case .loading(let requestID), .playing(let requestID), .failed(let requestID):
            requestID
        }
    }
}
```

Make `SpeechService` conform to `ObservableObject`, add `@Published private(set) var playbackState: SpeechPlaybackState = .idle`, and change `speak` to accept a caller-created `requestID: UUID` with a default value so existing tests and non-overlay callers remain source-compatible:

```swift
@discardableResult
func speak(
    _ text: String,
    language: String?,
    provider: TTSProvider = .apple,
    useAmericanAccent: Bool = true,
    requestID: UUID = UUID(),
    performance: LookupPerformanceContext? = nil
) -> UUID
```

Return the accepted request ID. Keep `requestGeneration` as the authority for rejecting stale asynchronous callbacks.

**Step 4: Add one lifecycle callback protocol**

Replace the start-only observer with callbacks that report actual output events:

```swift
@MainActor
protocol SpeechAudioLifecycleObserving: AnyObject {
    func setLifecycleHandlers(
        didStart: @escaping @MainActor () -> Void,
        didFinish: @escaping @MainActor () -> Void,
        didFail: @escaping @MainActor () -> Void
    )
}
```

Update `AVFoundationSpeechAudioOutput` to retain handlers for the active Apple utterance and online player. Implement:

- `speechSynthesizer(_:didStart:)` -> `didStart`
- `speechSynthesizer(_:didFinish:)` -> `didFinish`
- `speechSynthesizer(_:didCancel:)` -> clear handlers without reporting a stale failure
- `audioPlayerDidFinishPlaying(_:successfully:)` -> `didFinish` when successful, otherwise `didFail`
- `audioPlayerDecodeErrorDidOccur(_:error:)` -> `didFail`

Clear all handlers from `stop()` so an explicitly stopped request cannot later publish completion.

**Step 5: Drive state from generation-safe callbacks**

Apply these transitions in `SpeechService`:

- Apple request: remain `idle` until accepted for submission, then report `playing` only from `didStart`.
- Online request: set `loading` before fetching and `playing` only when playback starts or is verifiably accepted by a non-observing test output.
- Natural finish: set `idle` only when both generation and request ID still match.
- Explicit stop: increment generation, cancel fetch, stop output, set `idle`.
- Final Apple fallback failure: set `failed` for the current request.

Preserve current performance instrumentation and online-to-Apple fallback behavior. Do not mark the request failed while a fallback is still possible.

**Step 6: Make the test spy control lifecycle events**

Update `SpeechAudioOutputSpy` to implement `SpeechAudioLifecycleObserving` and provide:

```swift
func fireLatestDidStart()
func fireLatestDidFinish()
func fireLatestDidFail()
```

Keep event handlers associated with individual play attempts so a stale callback can be fired deliberately in the replacement-request test.

**Step 7: Run the lifecycle tests**

Run the Task 1 test command again.

Expected: all `SpeechServiceTests` pass, including existing cancellation, fallback, performance, and debug-dump tests.

**Step 8: Commit the lifecycle change**

Only when explicitly requested by the user:

```bash
git add "SnapTra Translator/SpeechService.swift" "SnapTra TranslatorTests/SpeechServiceTests.swift"
git commit -m "feat(tts): expose playback lifecycle"
```

### Task 2: Add context-aware pronunciation actions to AppModel

**Files:**
- Modify: `SnapTra Translator/AppModel.swift:9-73, 156-197, 456-490, 1248-1277, 1450-1471, 1580-1605, 1690-1715, 1868-1890, 3581-3617`
- Test: `SnapTra TranslatorTests/LookupDirectionTests.swift`

**Step 1: Write failing request-context policy tests**

Add pure policy tests covering:

```swift
func testWordPronunciationUsesWordSourceTextAndProvider()
func testSentencePronunciationUsesOriginalSourceTextAndProvider()
func testPlaybackStateIsVisibleOnlyForMatchingRequest()
func testWhitespaceSourceTextCannotBePlayed()
```

Keep these tests independent from windows, OCR, networking, and AVFoundation by testing a small equatable request/presentation resolver.

**Step 2: Run the focused tests and verify they fail**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test \
  -only-testing:SnapTra_TranslatorTests/LookupDirectionTests
```

Expected: failure because no overlay pronunciation request or matching policy exists.

**Step 3: Define the overlay pronunciation context**

Add a minimal domain type near the overlay content models:

```swift
enum OverlayPronunciationKind: Equatable {
    case word
    case sentence
}

struct OverlayPronunciationRequest: Equatable {
    let id: UUID
    let kind: OverlayPronunciationKind
    let text: String
    let languageIdentifier: String?
}
```

Add a pure resolver that trims text, rejects empty input, and maps the current `OverlayContent` or `ParagraphOverlayContent` to a request. Sentence requests must always use `ParagraphOverlayContent.originalText`, never a translated service result.

**Step 4: Publish the active overlay request and forward speech updates**

In `AppModel`, add:

```swift
@Published private(set) var activePronunciationRequest: OverlayPronunciationRequest?
private(set) var speechPlaybackState: SpeechPlaybackState
```

Subscribe once to `speechService.$playbackState` in initialization, assign the mirrored state on the main actor, and forward `objectWillChange` through the published property. Clear the active request when speech returns to `idle` after completion or stop; retain it for `failed` so retry remains associated with the current content.

If the existing initializer structure makes a direct subscription awkward, expose a read-only `speechService` and subscribe with `AnyCancellable`; do not create a second `SpeechService` in the view.

**Step 5: Add one manual playback entry point**

Implement a method such as:

```swift
func playOverlayPronunciation(kind: OverlayPronunciationKind)
```

It must:

- resolve the request from the current overlay state;
- reject empty text;
- assign a new request ID on every click, including replay;
- select `wordTTSProvider` or `sentenceTTSProvider` by kind;
- use the request's source language and the existing accent setting;
- call `speechService.speak(..., requestID:)`.

Add a read-only helper that maps the service state to the current request only when both request ID and visible content still match.

**Step 6: Route every automatic playback path through the helper**

Replace direct `speechService.speak` calls at the existing word and sentence auto-play sites with one private `startPronunciation(request:performance:)` helper. Preserve when auto-play occurs and preserve lookup performance tracking for word lookup.

Do not toggle preferences in these methods. `playWordPronunciation` and `playSentencePronunciation` remain the only persisted auto-play switches.

**Step 7: Preserve cancellation semantics**

Ensure `cancelActiveLookupWork()` and `hideOverlay()` still call `stopSpeaking()`, clear the active pronunciation request, and publish `idle`. Starting a replacement lookup must invalidate the previous request before showing new content.

Closing the auto-play switch must not call `stopSpeaking()`.

**Step 8: Run the focused model-policy tests**

Run the Task 2 test command again.

Expected: all request resolution and matching tests pass.

**Step 9: Commit the model change**

Only when explicitly requested by the user:

```bash
git add "SnapTra Translator/AppModel.swift" "SnapTra TranslatorTests/LookupDirectionTests.swift"
git commit -m "feat(overlay): add pronunciation actions"
```

### Task 3: Build the reusable two-zone pronunciation capsule

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift:15-22, 782-844, 1123-1145, 1220-1238, 1773-1802`
- Test: `SnapTra TranslatorTests/ParagraphOverlayLayoutTests.swift`

**Step 1: Write failing presentation-policy tests**

Add tests for a small pure presentation resolver:

```swift
func testPronunciationPresentationShowsProgressWhileLoading()
func testPronunciationPresentationShowsPlayingIconWhilePlaying()
func testPronunciationPresentationShowsRetryAfterFailure()
func testPronunciationPresentationShowsFilledAutoIndicatorWhenEnabled()
func testPronunciationPresentationKeepsManualPlaybackEnabledWhenAutoPlayIsOff()
```

The resolver should return semantic icon/help/accessibility values, not `Color` or concrete SwiftUI views.

**Step 2: Run the focused tests and verify they fail**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test \
  -only-testing:SnapTra_TranslatorTests/ParagraphOverlayLayoutTests
```

Expected: failure because the pronunciation presentation policy does not exist.

**Step 3: Add the semantic presentation policy**

Define a small type below the existing overlay layout policies in `OverlayView.swift`:

```swift
enum OverlayPronunciationVisualState: Equatable {
    case idle
    case loading
    case playing
    case failed
}

struct OverlayPronunciationPresentation: Equatable {
    let visualState: OverlayPronunciationVisualState
    let playbackHelp: String
    let playbackAccessibilityLabel: String
    let autoPlayAccessibilityLabel: String
    let isPlaybackEnabled: Bool
    let isAutoPlayEnabled: Bool
}
```

Resolve labels separately for word and sentence contexts. Use localized source keys for all user-facing strings.

**Step 4: Add one reusable SwiftUI control**

Implement a private `OverlayPronunciationControl` in `OverlayView.swift` with:

- one shared capsule background and border;
- a left plain button with a minimum 22-point hit target;
- a progress indicator for `loading`;
- `speaker.wave.2` or `waveform` with accent color for `playing`;
- `exclamationmark` for `failed`;
- a normal speaker icon for `idle`;
- a divider between zones;
- a right plain button containing localized `Auto` plus `circle.fill` or `circle`;
- separate `.help`, `.accessibilityLabel`, and `.accessibilityValue` modifiers;
- no pause semantics and no animation that continuously relayouts the header.

Keep the control visually within approximately 22-24 points high. Prefer subtle opacity changes over shadows or a second nested capsule.

**Step 5: Insert the control in the word header**

Update `wordHeaderControlGroup` to receive the current `OverlayContent`, insert the pronunciation capsule before `CopyButton`, and invoke:

```swift
model.playOverlayPronunciation(kind: .word)
model.settings.playWordPronunciation.toggle()
```

Increase `wordHeaderControlGroupWidth` and recompute the existing `WordOverlayHeaderLayoutPolicy` reservation so long words still truncate rather than overlap the control. Keep copy and close behavior unchanged.

**Step 6: Insert the control in both sentence top-bar variants**

Pass `ParagraphOverlayContent` into `paragraphTopBar` and `paragraphOriginalTopBar` where available. Add the same capsule before region selection and pin/close controls. Bind it to sentence state and `playSentencePronunciation`.

For `paragraphLoadingView`, do not show an enabled play action because source text is not available. The right auto-play toggle may either remain visible or be omitted consistently; prefer showing it disabled only if doing so does not make the loading toolbar wider than the result toolbar.

When original text is hidden, continue deriving playback from `ParagraphOverlayContent.originalText` so the control remains usable.

**Step 7: Add localization keys**

**Files:**
- Modify: `SnapTra Translator/Localizable.xcstrings`

Add English and Simplified Chinese values for at least:

- `Auto`
- `Play word pronunciation`
- `Play sentence pronunciation`
- `Playing - click to restart`
- `Pronunciation failed - click to retry`
- `Word auto-play is on`
- `Word auto-play is off`
- `Sentence auto-play is on`
- `Sentence auto-play is off`

Reuse existing keys if equivalent localized strings already exist. Do not duplicate keys that differ only by punctuation.

**Step 8: Run the presentation-policy tests**

Run the Task 3 test command again.

Expected: all `ParagraphOverlayLayoutTests` pass.

**Step 9: Commit the UI change**

Only when explicitly requested by the user:

```bash
git add "SnapTra Translator/OverlayView.swift" "SnapTra Translator/Localizable.xcstrings" "SnapTra TranslatorTests/ParagraphOverlayLayoutTests.swift"
git commit -m "feat(overlay): add pronunciation control"
```

### Task 4: Verify synchronization, races, and build integrity

**Files:**
- Modify if needed: `SnapTra Translator/SpeechService.swift`
- Modify if needed: `SnapTra Translator/AppModel.swift`
- Modify if needed: `SnapTra Translator/OverlayView.swift`
- Modify if needed: corresponding focused test files

**Step 1: Run the complete test suite**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test
```

Expected: all tests pass. Fix only regressions caused by this feature.

**Step 2: Run a Debug build**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected: `BUILD SUCCEEDED` with no Swift concurrency or actor-isolation errors.

**Step 3: Perform manual acceptance checks**

Run the app from Xcode and verify:

1. A word lookup displays the capsule and auto-plays according to the word setting.
2. A sentence lookup displays the capsule and speaks only the source text.
3. Manual play works while auto-play is off.
4. Clicking while playing restarts from the beginning.
5. Online providers show loading before playing.
6. Natural completion returns the icon to idle.
7. Closing or replacing the overlay stops audio immediately.
8. Switching the auto setting updates the existing settings UI and menu item.
9. Switching auto-play off does not stop current audio; switching it on does not immediately start audio.
10. Failure displays retry feedback without a modal.
11. Word and sentence settings remain independent after relaunch.
12. Long words, hidden sentence originals, pinned overlays, light mode, dark mode, keyboard focus, and VoiceOver labels remain usable.

**Step 4: Inspect the final diff**

Run:

```bash
git status --short
```

Expected: only the planned implementation, tests, localization, and plan documents changed; `git diff --check` reports no whitespace errors.

**Step 5: Create a final commit**

Only when explicitly requested by the user and only if the work was not already committed task-by-task:

```bash
git add "SnapTra Translator/SpeechService.swift" "SnapTra Translator/AppModel.swift" "SnapTra Translator/OverlayView.swift" "SnapTra Translator/Localizable.xcstrings" "SnapTra TranslatorTests/SpeechServiceTests.swift" "SnapTra TranslatorTests/LookupDirectionTests.swift" "SnapTra TranslatorTests/ParagraphOverlayLayoutTests.swift" "docs/plans/2026-08-31-overlay-pronunciation-control-design.md" "docs/plans/2026-08-31-overlay-pronunciation-control-plan.md"
git commit -m "feat(overlay): add pronunciation playback controls"
```
