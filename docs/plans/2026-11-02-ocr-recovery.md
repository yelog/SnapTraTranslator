# OCR Recovery Implementation Plan

> **For Claude:** Implement in the current authorized session. Do not commit or discard existing changes.

**Goal:** Recover from intermittent Vision engine errors and stalled synchronous calls without requiring users to restart or clear caches.

**Architecture:** Accurate and fast recognition each have a single bounded physical worker. A deadline or cancellation resumes the caller independently of the physical Vision call; an unresponsive call retains its worker slot until it actually exits. An occupied/timed-out accurate engine can fall back to fast recognition only when the source language is supported. Successful fallback lasts 60 seconds before accurate recovery is probed again. Startup OCR warmup is removed.

**Tech Stack:** Swift, Vision, Dispatch, XCTest, CoreText synthetic integration image, string catalogs.

---

## Evidence and correction

The first implementation used one serial queue for warmup and real OCR and assumed that request cancellation would eventually free it promptly. User logs showed accurate warmup starting at 400×80 followed by a successful foreground screenshot with no foreground OCR start. A regression test with a recognizer that ignores cancellation reproduced the blockage: the second lookup did not complete before the first physical call was released.

System E5 model resource warnings are evidence of a framework initialization problem; neither the logs nor the tests establish that the model cache is permanently damaged.

## Implementation

1. Remove startup OCR warmup from `AppModel.swift` and `OCRService.swift`.
2. In `OCRRecognitionExecutor.swift`, use one worker per engine with no physical work backlog. Keep at most two physical recognition calls in flight per executor.
3. Use lock-protected, exactly-once continuation completion for cancellation, deadline, and late framework results. Keep expired workers occupied until their physical calls exit; do not pretend a Swift deadline terminates Vision.
4. Use a 1-second accurate deadline and a 2-second fast deadline, injectable for tests. Include language capability queries and request configuration within the corresponding worker's deadline.
5. On an accurate engine failure, timeout, or occupied worker, try fast recognition only if the source language is supported. Unsupported languages preserve the accurate error. Do not retry cancellation, empty success, or unrelated errors.
6. Keep the 60-second monotonic per-language cooldown and stale-lookup UI guards. Log modes, revisions, elapsed time, engine errors, timeout/busy reasons, fallback activation and recovery without user text.

## Verification

- Deterministic tests cover normal fallback/recovery, unsupported languages, failures, accurate calls that ignore cancellation, prompt cancellation completion, timeouts, occupied workers, bounded work across repeated requests, and stalled capability queries.
- Run OCR recovery tests and existing OCR paragraph/token/bounding-box tests using the App Store scheme.
- Separately run `OCRVisionIntegrationTests/testVisionRecognizesSyntheticEnglish` in the actual app test host using the real Vision framework.
- Build the Direct scheme, validate project/catalog syntax, and inspect the final diff.
- Real-world E5 initialization failures remain OS-dependent. If both engine calls are unresponsive, the app returns an OCR error within bounded waiting rather than waiting indefinitely; in-process code cannot force-kill those framework calls.

## Validation results

- Before correction: the new cancellation-resistant stall regression failed with a 0.5-second expectation timeout and the wrong second execution mode, reproducing the reported blockage.
- After correction: 18 deterministic recovery tests and 29 existing OCR tests passed (47 total).
- Two real Vision integration tests passed: normal accurate recognition, and real fast recognition while a simulated accurate worker ignored cancellation. The latter completed in about 0.20 seconds.
- The real Vision test also emitted the reported E5 resource warnings while successfully recognizing text, so those warnings alone are not a failure verdict.
- Final combined run: 49 tests passed, 0 failures. The deliberately blocked test workers produced one Thread Performance Checker priority-inversion warning.
- Direct Debug build passed; project syntax, catalog JSON, and diff whitespace checks passed.
- No application cache was deleted, and no commit or push was performed.
