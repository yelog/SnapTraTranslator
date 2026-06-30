# Offline Enhanced In-Place Overlay Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve in-place sentence translation so translated text visually follows the original OCR text area instead of appearing as a centered panel.

**Architecture:** Keep the existing OCR and translation pipeline unchanged. Add a lightweight rendering style layer that derives background and foreground colors from the captured screenshot, maps OCR line boxes into the overlay window coordinate space, and lays translated text from the source text origin using adaptive typography. This is still an overlay, not true image inpainting or replacement of the underlying app content.

**Tech Stack:** Swift, SwiftUI, AppKit `NSPanel`, ScreenCaptureKit `CGImage`, XCTest, existing `CaptureExclusionRegistry`, existing OCR line boxes from Vision.

---

## Scope And Non-Goals

### In Scope

- Keep the existing `SentenceTranslationPresentationMode.inPlace` setting.
- Use the screenshot already captured for OCR to estimate the local background color.
- Estimate a readable foreground text color from sampled background luminance.
- Use OCR line rectangles to align the translated text container with the original text origin.
- Change the overlay from centered card-style rendering to top-leading source-aligned rendering.
- Keep fallback behavior for small, empty, or very long regions.
- Add deterministic unit tests for layout and color/style decisions.

### Out Of Scope

- No real background erasing or image inpainting.
- No character-level or word-level replacement.
- No exact baseline matching.
- No font-family detection.
- No cloud vision model or image translation API.
- No new third-party dependency.
- No user-facing advanced settings unless manual testing proves the default is risky.

## Architectural Assessment

The current feature is architecturally well placed: `AppModel` decides whether a sentence translation should use the normal panel or the in-place overlay, and `InPlaceTranslationWindowController` owns a non-interactive, capture-excluded `NSPanel`. The weakness is that `InPlaceTranslationView` ignores most source geometry. It receives `sourceLineRects`, but renders a single centered `Text` over a rounded material background.

The enhanced overlay should preserve this separation:

- `AppModel` remains orchestration only.
- `InPlaceTranslation.swift` owns rendering models, layout math, style estimation, and window display.
- `ScreenCaptureService` remains unchanged because it already returns `CGImage`, screen rect, and scale factor.
- Tests target pure layout/style helpers, not UI rendering.

The main architectural risk is mixing screen coordinates, capture coordinates, and window-local coordinates. Keep those conversions explicit and covered by tests.

## Positioning Guarantees

This plan supports visual alignment, not strict text identity alignment.

Guaranteed:

- The overlay window matches the OCR source rect.
- The translated text starts near the original first line's top-left position.
- The translated text wraps inside the original OCR region width.
- Single-line source text no longer renders centered vertically or horizontally.
- Multi-line source text uses the full OCR paragraph area and aligns from the first line origin.

Not guaranteed:

- Translated words line up with original words.
- Translated lines match original line count.
- Baselines match exactly.
- Complex backgrounds look natural.
- The original text is actually removed from the underlying app.

## Design

### Rendering Model

Add a style object to `InPlaceTranslationContent`:

```swift
struct InPlaceTranslationStyle: Equatable {
    var backgroundColor: NSColor
    var foregroundColor: NSColor
    var backgroundOpacity: CGFloat
    var materialOpacity: CGFloat
}
```

Add a resolved geometry object:

```swift
struct InPlaceTranslationTextFrame: Equatable {
    var origin: CGPoint
    var size: CGSize
}
```

Extend `InPlaceTranslationLayoutResult`:

```swift
struct InPlaceTranslationLayoutResult: Equatable {
    let fontSize: CGFloat
    let padding: CGFloat
    let cornerRadius: CGFloat
    let textFrame: InPlaceTranslationTextFrame
}
```

### Style Resolution

Create a pure helper in `InPlaceTranslation.swift`:

```swift
enum InPlaceTranslationStyleResolver {
    static func resolve(
        captureImage: CGImage?,
        captureRect: CGRect,
        sourceRect: CGRect,
        sourceLineRects: [CGRect]
    ) -> InPlaceTranslationStyle
}
```

The helper should:

- Convert `sourceRect` from screen points to image pixels using `captureRect` and `captureImage.width/height`.
- Sample a bounded grid of pixels inside the source rect, not every pixel.
- Prefer outer pixels or the whole region average for v1. Do not try to segment text pixels.
- Compute relative luminance.
- Use dark foreground on light backgrounds and light foreground on dark backgrounds.
- Return safe defaults when `captureImage` is nil or coordinate conversion fails.

Recommended defaults:

```swift
backgroundColor: NSColor.windowBackgroundColor
foregroundColor: NSColor.labelColor
backgroundOpacity: 0.72
materialOpacity: 0.22
```

Recommended contrast colors:

```swift
light background -> foreground: calibratedWhite 0.08 alpha 1
dark background -> foreground: calibratedWhite 0.96 alpha 1
```

### Layout Resolution

Update `InPlaceTranslationLayout.resolve(...)` to accept line rects:

```swift
static func resolve(
    sourceRect: CGRect,
    sourceLineRects: [CGRect],
    preferredFontSize: CGFloat,
    translatedText: String
) -> InPlaceTranslationLayoutResult
```

Rules:

- Convert `sourceLineRects` from screen coordinates to source-window-local coordinates by subtracting `sourceRect.minX` and `sourceRect.minY`.
- Use the first valid local line rect as the text anchor.
- Clamp anchor to the source window bounds.
- Use a small inset so text does not touch the edge.
- For a single source line, use a text frame starting at the first line origin with height equal to the whole source rect minus inset. This allows wrapping when translated text is longer.
- For multiple source lines, use a text frame from first line minY to the source rect bottom, with width from first line minX to source rect maxX.
- Fallback to top-leading full rect if line rects are empty or invalid.

Recommended algorithm:

```swift
let lineInset = max(2, min(6, sourceRect.height * 0.06))
let localLines = sourceLineRects
    .map { CGRect(x: $0.minX - sourceRect.minX, y: $0.minY - sourceRect.minY, width: $0.width, height: $0.height) }
    .filter { $0.width > 1 && $0.height > 1 }
let anchor = localLines.sorted { $0.minY < $1.minY }.first
let x = clamp((anchor?.minX ?? 0) + lineInset, min: lineInset, max: sourceRect.width - lineInset)
let y = clamp((anchor?.minY ?? 0) + lineInset, min: lineInset, max: sourceRect.height - lineInset)
let width = max(20, sourceRect.width - x - lineInset)
let height = max(16, sourceRect.height - y - lineInset)
```

Use existing font-size rules as the starting point, then tighten them:

- Minimum font size: `10`.
- Maximum font size: `22`.
- Source height cap: `height * 0.58` for single-line source, `averageLineHeight * 0.82` for multi-line source.
- Long translation penalties stay as currently implemented.

### View Rendering

Update `InPlaceTranslationView`:

- Use a `ZStack(alignment: .topLeading)`.
- Draw background over the entire source rect with sampled color and a small material layer.
- Place `Text(displayText)` at `layout.textFrame.origin`.
- Constrain it to `layout.textFrame.size`.
- Use `.multilineTextAlignment(.leading)`.
- Remove `.frame(... alignment: .center)`.
- Use `content.style.foregroundColor`.

Sketch:

```swift
ZStack(alignment: .topLeading) {
    RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
        .fill(Color(nsColor: content.style.backgroundColor).opacity(content.style.backgroundOpacity))
        .background(.regularMaterial.opacity(content.style.materialOpacity))

    Text(displayText)
        .font(.system(size: layout.fontSize, weight: .semibold))
        .foregroundStyle(Color(nsColor: content.style.foregroundColor))
        .multilineTextAlignment(.leading)
        .lineLimit(nil)
        .minimumScaleFactor(0.55)
        .frame(width: layout.textFrame.size.width, height: layout.textFrame.size.height, alignment: .topLeading)
        .position(
            x: layout.textFrame.origin.x + layout.textFrame.size.width / 2,
            y: layout.textFrame.origin.y + layout.textFrame.size.height / 2
        )
}
```

### AppModel Integration

Change `showInPlaceTranslationLoading(...)` to accept capture context:

```swift
private func showInPlaceTranslationLoading(
    originalText: String,
    rect: CGRect,
    lineRects: [CGRect],
    bodyFontSize: CGFloat,
    captureImage: CGImage?,
    captureRect: CGRect
)
```

Call `InPlaceTranslationStyleResolver.resolve(...)` inside this method and store the style in `InPlaceTranslationContent`.

Update all call sites:

- Cursor single-line path around `SnapTra Translator/AppModel.swift:1275`.
- Cursor paragraph path around `SnapTra Translator/AppModel.swift:1371`.
- Manual region path around `SnapTra Translator/AppModel.swift:1504`.

## Task 1: Add Layout Tests For Source-Aligned Text

**Files:**

- Modify: `SnapTra TranslatorTests/InPlaceTranslationLayoutTests.swift`
- Modify: `SnapTra Translator/InPlaceTranslation.swift`

**Step 1: Add failing tests**

Add tests for source-relative text frame calculation:

```swift
func testResolveAlignsTextFrameToFirstSourceLine() {
    let sourceRect = CGRect(x: 100, y: 200, width: 300, height: 120)
    let result = InPlaceTranslationLayout.resolve(
        sourceRect: sourceRect,
        sourceLineRects: [CGRect(x: 130, y: 230, width: 180, height: 24)],
        preferredFontSize: 18,
        translatedText: "需要软件更新"
    )

    XCTAssertGreaterThanOrEqual(result.textFrame.origin.x, 30)
    XCTAssertGreaterThanOrEqual(result.textFrame.origin.y, 30)
    XCTAssertLessThan(result.textFrame.origin.x, 40)
    XCTAssertLessThan(result.textFrame.origin.y, 40)
    XCTAssertGreaterThan(result.textFrame.size.width, 240)
    XCTAssertGreaterThan(result.textFrame.size.height, 70)
}

func testResolveFallsBackToTopLeadingWhenLineRectsAreEmpty() {
    let result = InPlaceTranslationLayout.resolve(
        sourceRect: CGRect(x: 0, y: 0, width: 220, height: 80),
        sourceLineRects: [],
        preferredFontSize: 16,
        translatedText: "Fallback"
    )

    XCTAssertGreaterThanOrEqual(result.textFrame.origin.x, 2)
    XCTAssertGreaterThanOrEqual(result.textFrame.origin.y, 2)
    XCTAssertGreaterThan(result.textFrame.size.width, 180)
    XCTAssertGreaterThan(result.textFrame.size.height, 50)
}

func testResolveKeepsTextFrameInsideSourceBounds() {
    let result = InPlaceTranslationLayout.resolve(
        sourceRect: CGRect(x: 100, y: 100, width: 140, height: 40),
        sourceLineRects: [CGRect(x: 230, y: 135, width: 200, height: 20)],
        preferredFontSize: 16,
        translatedText: "Long translated text"
    )

    XCTAssertGreaterThanOrEqual(result.textFrame.origin.x, 0)
    XCTAssertGreaterThanOrEqual(result.textFrame.origin.y, 0)
    XCTAssertLessThanOrEqual(result.textFrame.origin.x + result.textFrame.size.width, 140)
    XCTAssertLessThanOrEqual(result.textFrame.origin.y + result.textFrame.size.height, 40)
}
```

**Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test -only-testing:SnapTra_TranslatorTests/InPlaceTranslationLayoutTests
```

Expected: compile failure because `resolve` does not accept `sourceLineRects`, or test failure because `textFrame` does not exist.

**Step 3: Implement minimal layout model**

In `SnapTra Translator/InPlaceTranslation.swift`:

- Add `InPlaceTranslationTextFrame`.
- Add `textFrame` to `InPlaceTranslationLayoutResult`.
- Update `resolve` signature.
- Update existing call sites in tests and view.
- Implement clamped line-origin text frame calculation.

**Step 4: Run tests and verify pass**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test -only-testing:SnapTra_TranslatorTests/InPlaceTranslationLayoutTests
```

Expected: all `InPlaceTranslationLayoutTests` pass.

**Step 5: Commit**

```bash
git add "SnapTra Translator/InPlaceTranslation.swift" "SnapTra TranslatorTests/InPlaceTranslationLayoutTests.swift"
git commit -m "test(sentence): cover in-place source alignment"
```

## Task 2: Add Screenshot-Based Style Resolver

**Files:**

- Modify: `SnapTra Translator/InPlaceTranslation.swift`
- Modify: `SnapTra TranslatorTests/InPlaceTranslationLayoutTests.swift`

**Step 1: Add failing tests**

Add tests for style fallback and luminance decisions. Prefer testing pure helpers without requiring real display capture.

```swift
func testStyleResolverUsesDarkTextOnLightBackground() {
    let image = makeSolidImage(red: 0.95, green: 0.95, blue: 0.95)
    let style = InPlaceTranslationStyleResolver.resolve(
        captureImage: image,
        captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
        sourceRect: CGRect(x: 10, y: 10, width: 40, height: 30),
        sourceLineRects: []
    )

    XCTAssertLessThan(style.foregroundColor.relativeTestLuminance, 0.5)
}

func testStyleResolverUsesLightTextOnDarkBackground() {
    let image = makeSolidImage(red: 0.05, green: 0.05, blue: 0.05)
    let style = InPlaceTranslationStyleResolver.resolve(
        captureImage: image,
        captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
        sourceRect: CGRect(x: 10, y: 10, width: 40, height: 30),
        sourceLineRects: []
    )

    XCTAssertGreaterThan(style.foregroundColor.relativeTestLuminance, 0.5)
}

func testStyleResolverReturnsDefaultsWithoutImage() {
    let style = InPlaceTranslationStyleResolver.resolve(
        captureImage: nil,
        captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
        sourceRect: CGRect(x: 10, y: 10, width: 40, height: 30),
        sourceLineRects: []
    )

    XCTAssertGreaterThan(style.backgroundOpacity, 0)
    XCTAssertGreaterThan(style.materialOpacity, 0)
}
```

Add test-only helpers in the test file:

```swift
private func makeSolidImage(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
    let width = 10
    let height = 10
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        pixels[index] = UInt8(blue * 255)
        pixels[index + 1] = UInt8(green * 255)
        pixels[index + 2] = UInt8(red * 255)
        pixels[index + 3] = 255
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

private extension NSColor {
    var relativeTestLuminance: CGFloat {
        let color = usingColorSpace(.deviceRGB) ?? self
        return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    }
}
```

**Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test -only-testing:SnapTra_TranslatorTests/InPlaceTranslationLayoutTests
```

Expected: compile failure because `InPlaceTranslationStyleResolver` does not exist.

**Step 3: Implement style resolver**

In `SnapTra Translator/InPlaceTranslation.swift`:

- Add `InPlaceTranslationStyle`.
- Add `InPlaceTranslationStyleResolver`.
- Add internal helpers:
  - `pixelRect(for:captureRect:image:)`.
  - `averageColor(in:pixelRect:image:)`.
  - `relativeLuminance(for:)`.
- Use a small sampling grid such as max `16 x 16` samples.
- Clamp pixel rect to image bounds.

Implementation note: ScreenCaptureKit output uses BGRA. When reading raw data from `CGImage`, normalize through a known `CGContext` format instead of assuming the source image bitmap layout. Draw into a small RGBA buffer, then sample that buffer.

**Step 4: Run tests and verify pass**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test -only-testing:SnapTra_TranslatorTests/InPlaceTranslationLayoutTests
```

Expected: all in-place layout/style tests pass.

**Step 5: Commit**

```bash
git add "SnapTra Translator/InPlaceTranslation.swift" "SnapTra TranslatorTests/InPlaceTranslationLayoutTests.swift"
git commit -m "feat(sentence): estimate in-place overlay colors"
```

## Task 3: Wire Capture Style Into AppModel

**Files:**

- Modify: `SnapTra Translator/AppModel.swift`
- Modify: `SnapTra Translator/InPlaceTranslation.swift`

**Step 1: Update content model**

Add style to `InPlaceTranslationContent`:

```swift
struct InPlaceTranslationContent: Equatable {
    var originalText: String
    var translationState: InPlaceTranslationState
    var sourceRect: CGRect
    var sourceLineRects: [CGRect]
    var bodyFontSize: CGFloat
    var style: InPlaceTranslationStyle
}
```

**Step 2: Update AppModel helper signature**

Change `showInPlaceTranslationLoading(...)`:

```swift
private func showInPlaceTranslationLoading(
    originalText: String,
    rect: CGRect,
    lineRects: [CGRect],
    bodyFontSize: CGFloat,
    captureImage: CGImage?,
    captureRect: CGRect
)
```

Inside it:

```swift
let style = InPlaceTranslationStyleResolver.resolve(
    captureImage: captureImage,
    captureRect: captureRect,
    sourceRect: rect,
    sourceLineRects: lineRects
)
```

Pass `style` into `InPlaceTranslationContent`.

**Step 3: Update call sites**

Cursor single-line path:

```swift
showInPlaceTranslationLoading(
    originalText: text,
    rect: lineRect,
    lineRects: [lineRect],
    bodyFontSize: initialContent.bodyFontSize,
    captureImage: capture.image,
    captureRect: capture.region.rect
)
```

Cursor paragraph path:

```swift
showInPlaceTranslationLoading(
    originalText: paragraph.text,
    rect: paragraphRect,
    lineRects: paragraph.lines.map { screenRect(for: $0.boundingBox, in: capture.region.rect) },
    bodyFontSize: bodyFontSize,
    captureImage: capture.image,
    captureRect: capture.region.rect
)
```

Manual region path:

```swift
showInPlaceTranslationLoading(
    originalText: text,
    rect: capture.region.rect,
    lineRects: lines.map { screenRect(for: $0.boundingBox, in: capture.region.rect) },
    bodyFontSize: bodyFontSize,
    captureImage: capture.image,
    captureRect: capture.region.rect
)
```

**Step 4: Compile**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

**Step 5: Commit**

```bash
git add "SnapTra Translator/AppModel.swift" "SnapTra Translator/InPlaceTranslation.swift"
git commit -m "feat(sentence): style in-place overlay from capture"
```

## Task 4: Render Source-Aligned Enhanced Overlay

**Files:**

- Modify: `SnapTra Translator/InPlaceTranslation.swift`

**Step 1: Update `InPlaceTranslationView`**

Replace centered rendering with source-aligned rendering:

```swift
var body: some View {
    ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
            .fill(Color(nsColor: content.style.backgroundColor).opacity(content.style.backgroundOpacity))
            .background(.regularMaterial.opacity(content.style.materialOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: content.style.foregroundColor).opacity(0.12), lineWidth: 0.5)
            )

        Text(displayText)
            .font(.system(size: layout.fontSize, weight: .semibold))
            .foregroundStyle(Color(nsColor: content.style.foregroundColor))
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .minimumScaleFactor(0.55)
            .frame(
                width: layout.textFrame.size.width,
                height: layout.textFrame.size.height,
                alignment: .topLeading
            )
            .position(
                x: layout.textFrame.origin.x + layout.textFrame.size.width / 2,
                y: layout.textFrame.origin.y + layout.textFrame.size.height / 2
            )
    }
}
```

**Step 2: Run focused tests**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test -only-testing:SnapTra_TranslatorTests/InPlaceTranslationLayoutTests
```

Expected: tests pass.

**Step 3: Run Debug build**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

**Step 4: Manual verification**

In Xcode, run the app and verify:

- Default `Translation Panel` mode still opens the old panel.
- `In-place` mode opens an overlay at the OCR source rect.
- Single-line text starts near the original line, not centered.
- Multi-line text starts near the first line and wraps inside source bounds.
- Light background uses dark text.
- Dark background uses light text.
- Esc closes the overlay.
- Consecutive translations do not leave stale overlays.
- Subsequent screenshots do not capture the overlay.

**Step 5: Commit**

```bash
git add "SnapTra Translator/InPlaceTranslation.swift"
git commit -m "feat(sentence): align in-place overlay text to source"
```

## Task 5: Full Regression Verification

**Files:**

- No source changes expected.

**Step 1: Run settings tests**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test -only-testing:SnapTra_TranslatorTests/SettingsStoreMigrationTests
```

Expected: tests pass.

**Step 2: Run full test suite**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test
```

Expected: `** TEST SUCCEEDED **`.

**Step 3: Run release-safety build**

Run:

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

**Step 4: Inspect git status**

Run:

```bash
git status --short
git log --oneline -5
```

Expected: working tree clean, recent commits match the task commits.

## Risk Register

### Risk: Color Sampling Reads Wrong Pixel Format

Mitigation: Draw `CGImage` into a known RGBA bitmap context before sampling. Unit-test with generated solid images.

### Risk: Coordinate Conversion Flips Y Incorrectly

Mitigation: Use capture-local screen coordinates first. Because `captureRect` and `sourceRect` are both AppKit screen coordinates and `CGImage` represents the same captured rect, convert with normalized x/y and clamp. If manual testing shows vertical mismatch, add a focused test for top-left and bottom-right sampled colors.

### Risk: Overlay Looks Too Opaque

Mitigation: Keep `backgroundOpacity` below `0.8` and `materialOpacity` below `0.3`. Tune manually after first build.

### Risk: Complex Background Looks Worse

Mitigation: Do not overfit v1. Keep fallback to normal translation panel available through settings. Avoid aggressive blur/inpainting.

### Risk: Long Translation Overflows

Mitigation: Keep existing length penalty and `minimumScaleFactor`. Do not increase max font size beyond `22`.

## Final Acceptance Criteria

- In-place mode no longer centers the translated text inside the OCR rect.
- Translated text starts near the original first OCR line.
- Overlay foreground contrasts with sampled local background.
- Existing normal translation panel behavior remains unchanged.
- Unit tests cover layout alignment and color resolution.
- `xcodebuild ... test` passes.
- `xcodebuild ... Debug build` succeeds.
