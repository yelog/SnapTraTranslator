import XCTest
@testable import SnapTra_Translator

final class InPlaceTranslationLayoutTests: XCTestCase {
    func testResolveKeepsSmallLineReadableAndInsideHeight() {
        let result = InPlaceTranslationLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 180, height: 24),
            preferredFontSize: 18,
            translatedText: "短句翻译"
        )

        XCTAssertEqual(result.padding, 4)
        XCTAssertEqual(result.cornerRadius, 4)
        XCTAssertLessThanOrEqual(result.fontSize, 24 * 0.48)
        XCTAssertGreaterThanOrEqual(result.fontSize, 10)
    }

    func testResolveReducesFontForLongTranslations() {
        let short = InPlaceTranslationLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 420, height: 90),
            preferredFontSize: 18,
            translatedText: "短句翻译"
        )
        let long = InPlaceTranslationLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 420, height: 90),
            preferredFontSize: 18,
            translatedText: String(repeating: "这是一段较长的翻译内容", count: 8)
        )

        XCTAssertLessThan(long.fontSize, short.fontSize)
    }

    func testResolveCapsLargeTextAtMaximumFontSize() {
        let result = InPlaceTranslationLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 800, height: 300),
            preferredFontSize: 40,
            translatedText: "Large translation"
        )

        XCTAssertEqual(result.fontSize, 22)
        XCTAssertEqual(result.padding, 8)
        XCTAssertEqual(result.cornerRadius, 7)
    }

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

    func testStyleResolverReturnsOpaqueDefaultsWithoutImage() {
        let style = InPlaceTranslationStyleResolver.resolve(
            captureImage: nil,
            captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            sourceRect: CGRect(x: 10, y: 10, width: 40, height: 30),
            sourceLineRects: []
        )

        XCTAssertEqual(style.backgroundColor.alphaComponent, 1, accuracy: 0.001)
        XCTAssertEqual(style.borderColor.alphaComponent, 1, accuracy: 0.001)
    }

    func testStyleResolverUsesOpaqueBackgroundToCoverSourceText() {
        let image = makeSolidImage(red: 0.95, green: 0.95, blue: 0.95)
        let style = InPlaceTranslationStyleResolver.resolve(
            captureImage: image,
            captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            sourceRect: CGRect(x: 10, y: 10, width: 40, height: 30),
            sourceLineRects: []
        )

        XCTAssertEqual(style.backgroundColor.alphaComponent, 1, accuracy: 0.001)
        XCTAssertGreaterThan(style.backgroundColor.relativeTestLuminance, 0.9)
    }

    func testInPlacePresentationPolicyHidesLoadingWindow() {
        XCTAssertFalse(InPlaceTranslationPresentationPolicy.shouldShowWindow(for: .loading))
        XCTAssertTrue(InPlaceTranslationPresentationPolicy.shouldShowWindow(for: .ready("Translated text")))
        XCTAssertTrue(InPlaceTranslationPresentationPolicy.shouldShowWindow(for: .failed("Failed")))
    }

    func testImageTranslationLoadingAppearanceDoesNotDimOriginalImage() {
        XCTAssertEqual(InPlaceImageTranslationLoadingAppearance.backgroundOpacity, 0)
        XCTAssertLessThanOrEqual(InPlaceImageTranslationLoadingAppearance.beamHaloPeakOpacity, 0.38)
        XCTAssertLessThanOrEqual(InPlaceImageTranslationLoadingAppearance.beamCoreOpacity, 0.72)
    }

    func testImageTranslationLoadingScanBeamTravelsAcrossRegion() {
        let width: CGFloat = 240
        let start = InPlaceImageTranslationLoadingAppearance.beamCenterX(elapsed: 0, width: width)
        let middle = InPlaceImageTranslationLoadingAppearance.beamCenterX(
            elapsed: InPlaceImageTranslationLoadingAppearance.scanDuration,
            width: width
        )

        XCTAssertLessThan(start, 0)
        XCTAssertGreaterThan(middle, width)
    }
}

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
