import XCTest
@testable import SnapTra_Translator

final class OCRParagraphGroupingTests: XCTestCase {
    func testTokenTextsExtractsEnglishAndChineseTokensForChineseSourceLanguage() {
        let tokens = OCRService.tokenTexts(in: "HelloWorld 你好", language: "zh-Hans")

        XCTAssertEqual(tokens, ["Hello", "World", "你好"])
    }

    func testTokenTextsUsesChineseWordBoundariesForChineseSentence() {
        let sentence = "为什么很多人不相信农村老年人要养老金只有200块"
        let tokens = OCRService.tokenTexts(in: sentence, language: "zh-Hans")

        XCTAssertFalse(tokens.contains(sentence))
        XCTAssertTrue(tokens.contains("为什么"))
        XCTAssertTrue(tokens.contains("农村"))
        XCTAssertTrue(tokens.contains("老年人"))
        XCTAssertTrue(tokens.contains("养老金"))
    }

    func testTokenTextsKeepsNonLatinLetterTokensForFixedLanguageLookups() {
        let tokens = OCRService.tokenTexts(in: "東京 test")

        XCTAssertTrue(tokens.contains("東京"))
        XCTAssertTrue(tokens.contains("test"))
    }

    func testResolvedTokenBoundingBoxPrefersValidPreciseBox() {
        let parentBox = CGRect(x: 0.10, y: 0.40, width: 0.60, height: 0.10)
        let preciseBox = CGRect(x: 0.42, y: 0.41, width: 0.08, height: 0.07)
        let fallbackBox = CGRect(x: 0.38, y: 0.40, width: 0.12, height: 0.10)

        let result = OCRService.resolvedTokenBoundingBox(
            preciseBox: preciseBox,
            fallbackBox: fallbackBox,
            parentBox: parentBox
        )

        XCTAssertEqual(result, preciseBox)
    }

    func testResolvedTokenBoundingBoxFallsBackWhenPreciseBoxEscapesParent() {
        let parentBox = CGRect(x: 0.10, y: 0.40, width: 0.60, height: 0.10)
        let preciseBox = CGRect(x: 0.76, y: 0.41, width: 0.08, height: 0.07)
        let fallbackBox = CGRect(x: 0.52, y: 0.40, width: 0.12, height: 0.10)

        let result = OCRService.resolvedTokenBoundingBox(
            preciseBox: preciseBox,
            fallbackBox: fallbackBox,
            parentBox: parentBox
        )

        XCTAssertEqual(result, fallbackBox)
    }

    func testSelectWordPrefersStrictHitBeforeExpandedEarlierWord() {
        let words = [
            RecognizedWord(
                text: "用不了",
                boundingBox: CGRect(x: 0.365, y: 0.40, width: 0.15, height: 0.10)
            ),
            RecognizedWord(
                text: "突然",
                boundingBox: CGRect(x: 0.52, y: 0.40, width: 0.20, height: 0.10)
            ),
        ]

        let selected = OCRService.selectWord(
            from: words,
            normalizedPoint: CGPoint(x: 0.523, y: 0.45)
        )

        XCTAssertEqual(selected?.text, "突然")
    }

    func testSelectWordFallsBackToSmallToleranceWhenCursorIsJustOutsideBox() {
        let words = [
            RecognizedWord(
                text: "突然",
                boundingBox: CGRect(x: 0.52, y: 0.40, width: 0.12, height: 0.10)
            ),
        ]

        let selected = OCRService.selectWord(
            from: words,
            normalizedPoint: CGPoint(x: 0.517, y: 0.45)
        )

        XCTAssertEqual(selected?.text, "突然")
    }

    func testGroupsAlignedEnglishLinesIntoSingleParagraph() {
        let lines = [
            RecognizedTextLine(
                text: "This is the first line of a paragraph.",
                boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.46, height: 0.05)
            ),
            RecognizedTextLine(
                text: "This is the second line of the paragraph.",
                boundingBox: CGRect(x: 0.10, y: 0.64, width: 0.48, height: 0.05)
            ),
        ]

        let paragraphs = OCRService.groupParagraphs(from: lines)

        XCTAssertEqual(paragraphs.count, 1)
        XCTAssertEqual(
            paragraphs.first?.text,
            "This is the first line of a paragraph.\nThis is the second line of the paragraph."
        )
    }

    func testSelectsParagraphContainingPointerBeforeNearbyParagraph() {
        let paragraphs = [
            RecognizedParagraph(
                text: "First paragraph line one\nFirst paragraph line two",
                lines: [],
                boundingBox: CGRect(x: 0.10, y: 0.60, width: 0.40, height: 0.14)
            ),
            RecognizedParagraph(
                text: "Second paragraph line one\nSecond paragraph line two",
                lines: [],
                boundingBox: CGRect(x: 0.58, y: 0.58, width: 0.28, height: 0.12)
            ),
        ]

        let selected = OCRService.selectParagraph(
            from: paragraphs,
            normalizedPoint: CGPoint(x: 0.22, y: 0.66)
        )

        XCTAssertEqual(selected?.text, paragraphs[0].text)
    }

    func testIgnoresShortEnglishUiLabelsWhenBuildingParagraphs() {
        let lines = [
            RecognizedTextLine(
                text: "Download",
                boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.12, height: 0.04)
            ),
            RecognizedTextLine(
                text: "Settings",
                boundingBox: CGRect(x: 0.10, y: 0.64, width: 0.12, height: 0.04)
            ),
        ]

        let paragraphs = OCRService.groupParagraphs(from: lines)

        XCTAssertTrue(paragraphs.isEmpty)
    }

    func testKeepsShortMultiWordHeadingWhenBuildingParagraphs() {
        let lines = [
            RecognizedTextLine(
                text: "Master Plan",
                boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.18, height: 0.04)
            ),
        ]

        let paragraphs = OCRService.groupParagraphs(from: lines)

        XCTAssertEqual(paragraphs.map(\.text), ["Master Plan"])
    }

    func testParsesBulletLinesIntoListItemBlocks() {
        let lines = [
            RecognizedTextLine(
                text: "• Unlimited multi-agent parallel execution",
                boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.42, height: 0.04)
            ),
            RecognizedTextLine(
                text: "• Automated orchestration from analysis to deployment",
                boundingBox: CGRect(x: 0.10, y: 0.66, width: 0.50, height: 0.04)
            ),
        ]

        let structure = ParagraphTextStructure.fromRecognizedLines(lines)

        XCTAssertEqual(
            structure.blocks,
            [
                ParagraphTextBlock(
                    kind: .listItem(marker: "•"),
                    bodyLines: ["Unlimited multi-agent parallel execution"]
                ),
                ParagraphTextBlock(
                    kind: .listItem(marker: "•"),
                    bodyLines: ["Automated orchestration from analysis to deployment"]
                ),
            ]
        )
        XCTAssertEqual(
            structure.renderedText,
            "• Unlimited multi-agent parallel execution\n• Automated orchestration from analysis to deployment"
        )
    }

    func testMergesIndentedContinuationIntoPreviousListItem() {
        let lines = [
            RecognizedTextLine(
                text: "• CLI compatibility: Claude, Gemini, Codex,",
                boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.44, height: 0.04)
            ),
            RecognizedTextLine(
                text: "OpenCode, Qwen, OpenClaw",
                boundingBox: CGRect(x: 0.15, y: 0.66, width: 0.34, height: 0.04)
            ),
            RecognizedTextLine(
                text: "• Visual interface combined with command-line power",
                boundingBox: CGRect(x: 0.10, y: 0.60, width: 0.48, height: 0.04)
            ),
        ]

        let structure = ParagraphTextStructure.fromRecognizedLines(lines)

        XCTAssertEqual(
            structure.blocks,
            [
                ParagraphTextBlock(
                    kind: .listItem(marker: "•"),
                    bodyLines: [
                        "CLI compatibility: Claude, Gemini, Codex,",
                        "OpenCode, Qwen, OpenClaw",
                    ]
                ),
                ParagraphTextBlock(
                    kind: .listItem(marker: "•"),
                    bodyLines: ["Visual interface combined with command-line power"]
                ),
            ]
        )
    }

    func testApplyingTranslationsPreservesListMarkersAndOrder() {
        let structure = ParagraphTextStructure(
            blocks: [
                ParagraphTextBlock(kind: .listItem(marker: "•"), bodyLines: ["Unlimited multi-agent parallel execution"]),
                ParagraphTextBlock(kind: .plainLine, bodyLines: ["Keep existing shell behavior."]),
            ]
        )

        let rebuilt = structure.applyingTranslations(
            [
                "无限多代理并行执行",
                "保持现有面板行为。",
            ]
        )

        XCTAssertEqual(
            rebuilt,
            "• 无限多代理并行执行\n保持现有面板行为。"
        )
    }

    func testGroupParagraphsMergesSameBaselineFragmentsIntoSingleLine() {
        let lines = [
            RecognizedTextLine(
                text: "you",
                boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.10, height: 0.06)
            ),
            RecognizedTextLine(
                text: "test some word",
                boundingBox: CGRect(x: 0.24, y: 0.721, width: 0.34, height: 0.059)
            ),
        ]

        let paragraphs = OCRService.groupParagraphs(from: lines)

        XCTAssertEqual(paragraphs.count, 1)
        XCTAssertEqual(paragraphs.first?.text, "you test some word")
        XCTAssertEqual(paragraphs.first?.lines.count, 1)
        XCTAssertEqual(paragraphs.first?.lines.first?.text, "you test some word")
    }

    func testGroupParagraphsDoesNotMergeFarSameBaselineColumns() {
        let lines = [
            RecognizedTextLine(
                text: "Primary content",
                boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.20, height: 0.05)
            ),
            RecognizedTextLine(
                text: "Sidebar tools",
                boundingBox: CGRect(x: 0.56, y: 0.721, width: 0.18, height: 0.05)
            ),
        ]

        let paragraphs = OCRService.groupParagraphs(from: lines)

        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs.map(\.text), ["Primary content", "Sidebar tools"])
    }
}
