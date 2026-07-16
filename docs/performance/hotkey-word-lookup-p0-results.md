# Hotkey Word Lookup P0 Performance Results

## Measurement Contract

- Metric start: `AppModel.handleHotkeyTrigger()` accepts a single-press lookup.
- First panel proxy: `NSWindow.orderFrontRegardless()` returns for a previously hidden word panel.
- Existing panel update: `overlayState` publishes new word content; it is not counted as another order-front.
- Apple audio start: `AVSpeechSynthesizerDelegate.speechSynthesizer(_:didStart:)`.
- Online audio start proxy: `AVAudioPlayer.play()` returns `true` and `isPlaying` is true.
- All timings use a monotonic clock and the same business `lookupID`.

## Environment

| Field | Before | After |
| --- | --- | --- |
| Commit | `b660a56` | TBD |
| macOS | 26.5.2 (25F84) | TBD |
| Mac model / chip | Mac14,6 / Apple M2 Max | TBD |
| Display resolution / scale | Built-in 1496x967 @2x, external 1920x1080 @2x | TBD |
| Source / target language | TBD | TBD |
| Dictionary sources | TBD | TBD |
| TTS provider | TBD | TBD |
| Learning records | 0 / 100 / 5,000 | 0 / 100 / 5,000 |

## Sampling Rules

- Cold: first valid lookup after process launch; at least 5 samples per cell.
- Warm: three unrecorded warmups, then at least 20 samples per cell.
- Keep machine, display scale, language pair, dictionary sources, test text, and network conditions fixed.
- Record App Store OCR, Direct OCR/no-selection, Direct AX selection, and Direct fresh-clipboard fallback separately.
- Do not compare Direct selected-text timings against App Store OCR timings.

## Before Baseline

Functional baseline before instrumentation: `xcodebuild test` passed 233 tests with 0 failures on `b660a56`.

| Channel | Route | Temperature | Learning count | Samples | Panel P50 | Panel P95 | Audio P50 | Audio P95 | Trace |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| App Store | OCR | cold | 0 | TBD | TBD | TBD | TBD | TBD | TBD |
| App Store | OCR | warm | 0 | TBD | TBD | TBD | TBD | TBD | TBD |
| Direct | OCR / no selection | cold | 0 | TBD | TBD | TBD | TBD | TBD | TBD |
| Direct | OCR / no selection | warm | 0 | TBD | TBD | TBD | TBD | TBD | TBD |
| Direct | AX selection | warm | 0 | TBD | TBD | TBD | TBD | TBD | TBD |
| Direct | clipboard selection | warm | 0 | TBD | TBD | TBD | TBD | TBD | TBD |

## After P0

| Channel | Route | Temperature | Learning count | Samples | Panel P50 | Panel P95 | Audio P50 | Audio P95 | Trace |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| App Store | OCR | cold | 0 | TBD | TBD | TBD | TBD | TBD | TBD |
| App Store | OCR | warm | 0 | TBD | TBD | TBD | TBD | TBD | TBD |
| Direct | OCR / no selection | cold | 0 | TBD | TBD | TBD | TBD | TBD | TBD |
| Direct | OCR / no selection | warm | 0 | TBD | TBD | TBD | TBD | TBD | TBD |
| Direct | AX selection | warm | 0 | TBD | TBD | TBD | TBD | TBD | TBD |
| Direct | clipboard selection | warm | 0 | TBD | TBD | TBD | TBD | TBD | TBD |

## Stage Comparison

| Stage | Before P50 | Before P95 | After P50 | After P95 | Change | Notes |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Accessibility probe | TBD | TBD | TBD | TBD | TBD | Attribute reads: TBD |
| Clipboard fallback | TBD | TBD | TBD | TBD | TBD | Fresh/stale outcome: TBD |
| Capture metadata | TBD | TBD | TBD | TBD | TBD | Cache hit ratio: TBD |
| Screenshot | TBD | TBD | TBD | TBD | TBD | TBD |
| OCR | TBD | TBD | TBD | TBD | TBD | Accurate recognition retained |
| Panel presentation | TBD | TBD | TBD | TBD | TBD | order-front proxy |
| TTS fetch | TBD | TBD | TBD | TBD | TBD | Provider: TBD |
| Fetch end to play | TBD | TBD | TBD | TBD | TBD | Online proxy |
| Learning record | TBD | TBD | TBD | TBD | TBD | Save count: TBD |
| Learning definition | TBD | TBD | TBD | TBD | TBD | Save count: TBD |

## Correctness Gates

- [ ] Known-range AX selection remains selection-first without bounds.
- [ ] Stale clipboard never intercepts OCR lookup.
- [ ] Fresh clipboard wins even when speculative OCR completes first.
- [ ] App Store invokes neither AX nor clipboard fallback.
- [ ] Cached capture metadata never captures a registered overlay.
- [ ] Settings and other unregistered app windows remain capturable.
- [ ] Superseded or stopped TTS requests never play or fall back.
- [ ] HTTP and WebSocket cancellation reaches the underlying request.
- [ ] Lookup-time language full fetch count is zero.
- [ ] Each lookup performs one lookup save and zero or one definition save.
- [ ] Full matching-record export remains unchanged.

## Acceptance Summary

| Gate | Target | Result |
| --- | --- | --- |
| Direct OCR warm panel P50 | At least 25% faster | TBD |
| Direct OCR warm panel P95 | At least 20% faster | TBD |
| App Store OCR warm panel P95 | At least 10% faster | TBD |
| Any route P95 regression | No more than 5% | TBD |
| Capture metadata warm loads | One load per generation | TBD |
| Stale TTS effects | Zero | TBD |
| Learning 5,000 vs 100 P95 delta | No more than 5 ms | TBD |

## Exceptions And Raw Evidence

- Before traces: TBD
- After traces: TBD
- Outliers excluded: none unless documented here with a reproducible reason.
- Known baseline warnings: TBD
