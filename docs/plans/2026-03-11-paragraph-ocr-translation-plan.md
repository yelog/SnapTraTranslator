# Paragraph OCR Translation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a paragraph translation mode that upgrades the existing word popup in place on double-tap, performs full-display OCR on the current screen, highlights the English paragraph under the pointer, and shows original text plus translation in the same popup.

**Architecture:** Keep the current popup shell and request-cancellation model in `AppModel`, but add a non-blocking double-tap upgrade signal, a second screen-capture path for full-display OCR, and a richer OCR model that groups lines into paragraphs. Render paragraph loading and result states in the existing overlay view while a dedicated highlight window draws green corner markers around the selected paragraph.

**Tech Stack:** Swift, SwiftUI, AppKit, Vision, ScreenCaptureKit, XCTest, xcodebuild

---

### Task 1: Add non-blocking double-tap detection to the hotkey layer

**Files:**
- Modify: `SnapTra Translator/HotkeyManager.swift`
- Create: `SnapTra TranslatorTests/HotkeyManagerTests.swift`

**Step 1: Write the failing test**

```swift
func testSecondTapEmitsDoubleTapWithoutDelayingFirstTrigger() {
    let recorder = HotkeyEventRecorder()
    let manager = HotkeyManager(clock: recorder.clock)
    manager.onTrigger = { recorder.events.append(.trigger) }
    manager.onDoubleTap = { recorder.events.append(.doubleTap) }

    manager.handleTestTrigger()
    recorder.clock.advance(by: 0.08)
    manager.handleTestRelease()
    recorder.clock.advance(by: 0.08)
    manager.handleTestTrigger()

    XCTAssertEqual(recorder.events, [.trigger, .doubleTap])
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:'SnapTra TranslatorTests/HotkeyManagerTests/testSecondTapEmitsDoubleTapWithoutDelayingFirstTrigger'
```

Expected: FAIL because `onDoubleTap` and test hooks do not exist yet.

**Step 3: Write minimal implementation**

```swift
final class HotkeyManager {
    var onTrigger: (() -> Void)?
    var onRelease: (() -> Void)?
    var onDoubleTap: (() -> Void)?

    private var lastEligibleReleaseDate: Date?
    private let doubleTapInterval: TimeInterval = 0.25

    private func emitTrigger(now: Date) {
        onTrigger?()
        if let lastEligibleReleaseDate,
           now.timeIntervalSince(lastEligibleReleaseDate) <= doubleTapInterval {
            onDoubleTap?()
        }
    }
}
```

Implement the real release-eligibility rules in the production event path and expose a test seam for deterministic unit coverage.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild ... -only-testing:` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add "SnapTra Translator/HotkeyManager.swift" "SnapTra TranslatorTests/HotkeyManagerTests.swift"
git commit -m "feat: add non-blocking hotkey double tap detection"
```

### Task 2: Extend overlay state to support paragraph loading and paragraph results

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`
- Modify: `SnapTra Translator/OverlayView.swift`
- Modify: `SnapTra Translator/OverlayWindowController.swift`
- Create: `SnapTra TranslatorTests/OverlayModeTests.swift`

**Step 1: Write the failing test**

```swift
func testParagraphModeRendersOriginalAndTranslationWithoutDictionarySections() {
    let content = OverlayContent.paragraph(
        originalText: "This is a paragraph.",
        translatedText: "这是一段文字。"
    )

    XCTAssertEqual(content.displayMode, .paragraph)
    XCTAssertTrue(content.dictionarySections.isEmpty)
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:'SnapTra TranslatorTests/OverlayModeTests/testParagraphModeRendersOriginalAndTranslationWithoutDictionarySections'
```

Expected: FAIL because paragraph display mode does not exist.

**Step 3: Write minimal implementation**

```swift
enum OverlayState: Equatable {
    case idle
    case wordLoading(String?)
    case wordResult(OverlayWordContent)
    case paragraphLoading
    case paragraphResult(OverlayParagraphContent)
    case error(String)
    case noWord
}
```

Update `OverlayView` to switch on word and paragraph modes inside the same popup shell and widen paragraph layout constraints.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild ... -only-testing:` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add "SnapTra Translator/AppModel.swift" "SnapTra Translator/OverlayView.swift" "SnapTra Translator/OverlayWindowController.swift" "SnapTra TranslatorTests/OverlayModeTests.swift"
git commit -m "feat: add paragraph overlay modes"
```

### Task 3: Add full-display capture for the display under the pointer

**Files:**
- Modify: `SnapTra Translator/ScreenCaptureService.swift`
- Create: `SnapTra TranslatorTests/ScreenCaptureGeometryTests.swift`

**Step 1: Write the failing test**

```swift
func testDisplayLocalCoordinatesFlipYAxisForFullDisplayRect() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let rect = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    let converted = ScreenCaptureGeometry.displayLocalRect(for: rect, screenFrame: screenFrame)

    XCTAssertEqual(converted.origin.x, 0)
    XCTAssertEqual(converted.origin.y, 0)
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:'SnapTra TranslatorTests/ScreenCaptureGeometryTests/testDisplayLocalCoordinatesFlipYAxisForFullDisplayRect'
```

Expected: FAIL because reusable geometry helpers for full-display capture do not exist.

**Step 3: Write minimal implementation**

```swift
func captureCurrentDisplay(scaleDownFactor: CGFloat) async -> (image: CGImage, region: CaptureRegion)? {
    let mouseLocation = NSEvent.mouseLocation
    guard let screen = screen(containing: mouseLocation) else { return nil }
    let rectInScreen = screen.frame
    let cgRect = convertToDisplayLocalCoordinates(rectInScreen, screen: screen)
    let configuration = makeConfiguration(for: cgRect, scaleFactor: screen.backingScaleFactor / scaleDownFactor)
    ...
}
```

Refactor geometry helpers into pure functions so tests cover coordinate math without needing ScreenCaptureKit.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild ... -only-testing:` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add "SnapTra Translator/ScreenCaptureService.swift" "SnapTra TranslatorTests/ScreenCaptureGeometryTests.swift"
git commit -m "feat: add full-display capture for paragraph OCR"
```

### Task 4: Add OCR line and paragraph grouping with pointer hit-testing

**Files:**
- Modify: `SnapTra Translator/OCRService.swift`
- Create: `SnapTra TranslatorTests/OCRParagraphGroupingTests.swift`

**Step 1: Write the failing test**

```swift
func testGroupsAlignedEnglishLinesIntoOneParagraphAndSelectsPointerHit() {
    let lines = [
        RecognizedTextLine(text: "First line of text", boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.05)),
        RecognizedTextLine(text: "Second line of text", boundingBox: CGRect(x: 0.1, y: 0.62, width: 0.52, height: 0.05)),
    ]

    let paragraphs = OCRParagraphGrouper.group(lines)
    let selected = OCRParagraphSelector.select(from: paragraphs, pointer: CGPoint(x: 0.2, y: 0.66))

    XCTAssertEqual(paragraphs.count, 1)
    XCTAssertEqual(selected?.text, "First line of text\nSecond line of text")
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:'SnapTra TranslatorTests/OCRParagraphGroupingTests/testGroupsAlignedEnglishLinesIntoOneParagraphAndSelectsPointerHit'
```

Expected: FAIL because line and paragraph models do not exist.

**Step 3: Write minimal implementation**

```swift
struct RecognizedTextLine: Equatable {
    let text: String
    let boundingBox: CGRect
}

struct RecognizedParagraph: Equatable {
    let text: String
    let lines: [RecognizedTextLine]
    let boundingBox: CGRect
}
```

Add extraction and grouping helpers that:

- build lines from Vision observations
- merge neighboring lines into paragraphs
- filter to English-heavy paragraphs
- select the paragraph whose box contains the normalized pointer

**Step 4: Run test to verify it passes**

Run the same `xcodebuild ... -only-testing:` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add "SnapTra Translator/OCRService.swift" "SnapTra TranslatorTests/OCRParagraphGroupingTests.swift"
git commit -m "feat: add OCR paragraph grouping and hit testing"
```

### Task 5: Add paragraph highlight rendering with green corner markers

**Files:**
- Modify: `SnapTra Translator/OverlayWindowController.swift`
- Create: `SnapTra TranslatorTests/ParagraphHighlightGeometryTests.swift`

**Step 1: Write the failing test**

```swift
func testCornerSegmentsStayInsideParagraphBounds() {
    let rect = CGRect(x: 100, y: 200, width: 300, height: 120)
    let segments = ParagraphHighlightGeometry.cornerSegments(for: rect, cornerLength: 18)

    XCTAssertEqual(segments.count, 8)
    XCTAssertTrue(segments.allSatisfy { rect.insetBy(dx: -0.1, dy: -0.1).contains($0.start) && rect.insetBy(dx: -0.1, dy: -0.1).contains($0.end) })
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:'SnapTra TranslatorTests/ParagraphHighlightGeometryTests/testCornerSegmentsStayInsideParagraphBounds'
```

Expected: FAIL because production highlight geometry is not defined.

**Step 3: Write minimal implementation**

```swift
struct ParagraphHighlightGeometry {
    static func cornerSegments(for rect: CGRect, cornerLength: CGFloat) -> [LineSegment] {
        ...
    }
}
```

Replace the debug full-rectangle rendering with a dedicated highlight view that draws only the four green right-angle corners for the selected paragraph.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild ... -only-testing:` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add "SnapTra Translator/OverlayWindowController.swift" "SnapTra TranslatorTests/ParagraphHighlightGeometryTests.swift"
git commit -m "feat: add paragraph corner highlight overlay"
```

### Task 6: Integrate paragraph upgrade flow into AppModel

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`
- Modify: `SnapTra Translator/TranslationService.swift`
- Create: `SnapTra TranslatorTests/AppModelParagraphFlowTests.swift`

**Step 1: Write the failing test**

```swift
func testDoubleTapUpgradesExistingLookupToParagraphLoading() async {
    let model = AppModel.makeForTests()

    await model.handleHotkeyTrigger()
    await model.handleHotkeyDoubleTap()

    XCTAssertEqual(model.overlayState, .paragraphLoading)
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:'SnapTra TranslatorTests/AppModelParagraphFlowTests/testDoubleTapUpgradesExistingLookupToParagraphLoading'
```

Expected: FAIL because the paragraph upgrade flow is not wired.

**Step 3: Write minimal implementation**

```swift
func handleHotkeyDoubleTap() {
    lookupTask?.cancel()
    activeLookupID = UUID()
    updateOverlay(state: .paragraphLoading, anchor: overlayAnchor)
    startParagraphLookup()
}
```

Wire the paragraph lookup pipeline so it:

- cancels stale word work
- captures the current display
- runs OCR paragraph selection
- updates the highlight overlay
- translates the selected paragraph
- updates the same popup to `paragraphResult`

Keep stale-result guards and cancellation semantics aligned with the existing lookup pipeline.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild ... -only-testing:` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add "SnapTra Translator/AppModel.swift" "SnapTra Translator/TranslationService.swift" "SnapTra TranslatorTests/AppModelParagraphFlowTests.swift"
git commit -m "feat: integrate paragraph OCR upgrade flow"
```

### Task 7: Run regression coverage and manual QA checklist

**Files:**
- Modify: `docs/plans/2026-03-11-paragraph-ocr-translation-plan.md`

**Step 1: Run focused automated tests**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test -only-testing:'SnapTra TranslatorTests/HotkeyManagerTests' -only-testing:'SnapTra TranslatorTests/OverlayModeTests' -only-testing:'SnapTra TranslatorTests/ScreenCaptureGeometryTests' -only-testing:'SnapTra TranslatorTests/OCRParagraphGroupingTests' -only-testing:'SnapTra TranslatorTests/ParagraphHighlightGeometryTests' -only-testing:'SnapTra TranslatorTests/AppModelParagraphFlowTests'
```

Expected: PASS for the new focused suite.

**Step 2: Run broader regression test pass**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -destination 'platform=macOS' test
```

Expected: PASS for the full project test suite.

**Step 3: Execute manual QA**

Verify:

- first-trigger word lookup shows with no added delay
- second trigger upgrades the same popup to paragraph loading
- paragraph result uses the same popup shell
- green corner markers align with the selected paragraph
- release during paragraph OCR dismisses popup and highlight
- no English paragraph under pointer produces a clear paragraph-mode message

**Step 4: Record QA notes**

Append a short implementation note to this plan documenting:

- tested apps
- screens used
- observed latency
- any unresolved OCR edge cases

**Step 5: Commit**

```bash
git add "docs/plans/2026-03-11-paragraph-ocr-translation-plan.md"
git commit -m "docs: record paragraph OCR QA notes"
```
