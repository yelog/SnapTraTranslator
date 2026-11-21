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

    func testTokenTextsUsesChineseWordBoundariesInMixedScriptSentence() {
        let sentence = "生产环境的 Mysql 和 Redis 都是部署在哪里的呢"
        let tokens = OCRService.tokenTexts(in: sentence, language: "zh-Hans")

        XCTAssertTrue(tokens.contains("Mysql"))
        XCTAssertTrue(tokens.contains("Redis"))
        XCTAssertTrue(tokens.contains("部署"))
    }

    func testTokenTextsUsesChineseWordBoundariesForProductFeatureLabels() {
        let labels = [
            "用户登录": ["用户", "登录"],
            "权限管理": ["权限", "管理"],
            "审计日志管理": ["审计", "日志", "管理"],
            "多数据源管理": ["多", "数据", "源", "管理"],
        ]

        for (label, expectedTokens) in labels {
            let tokens = OCRService.tokenTexts(in: label, language: "zh-Hans")

            XCTAssertFalse(tokens.contains(label), "Expected '\(label)' to be split into word tokens")
            for expectedToken in expectedTokens {
                XCTAssertTrue(
                    tokens.contains(expectedToken),
                    "Expected '\(label)' tokens \(tokens) to contain '\(expectedToken)'"
                )
            }
        }
    }

    func testTokenTextsRecoversEnglishWordSkippedByTokenizerInMixedText() {
        let tokens = OCRService.tokenTexts(in: "1.词典选择：Apple Dictionary，原词典内容：", language: "zh-Hans")

        XCTAssertTrue(tokens.contains("Apple"))
        XCTAssertTrue(tokens.contains("Dictionary"))
    }

    func testTokenTextsKeepsNonLatinLetterTokensForFixedLanguageLookups() {
        let tokens = OCRService.tokenTexts(in: "東京 test")

        XCTAssertTrue(tokens.contains("東京"))
        XCTAssertTrue(tokens.contains("test"))
    }

    func testTokenTextsSplitsHyphenatedEnglishKeys() {
        let tokens = OCRService.tokenTexts(in: "embedding-dimension:")

        XCTAssertEqual(tokens, ["embedding", "dimension"])
    }

    func testTokenTextsSplitsCodeLikeValues() {
        XCTAssertEqual(OCRService.tokenTexts(in: "embedding-model:"), ["embedding", "model"])
        XCTAssertEqual(OCRService.tokenTexts(in: "embedding-url:"), ["embedding", "url"])
        XCTAssertEqual(OCRService.tokenTexts(in: "embeddingProvider:"), ["embedding", "Provider"])
        XCTAssertEqual(OCRService.tokenTexts(in: "qwen3-embedding:4b"), ["qwen", "embedding", "b"])
        XCTAssertEqual(OCRService.tokenTexts(in: "http://localhost:11434"), ["http", "localhost"])
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

    func testResolvedTokenBoundingBoxKeepsCompatibleSubrangePreciseBox() {
        let parentBox = CGRect(x: 0.10, y: 0.40, width: 0.60, height: 0.10)
        let preciseBox = CGRect(x: 0.39, y: 0.41, width: 0.20, height: 0.08)
        let fallbackBox = CGRect(x: 0.37, y: 0.40, width: 0.24, height: 0.10)

        let result = OCRService.resolvedTokenBoundingBox(
            preciseBox: preciseBox,
            fallbackBox: fallbackBox,
            parentBox: parentBox,
            isSubrange: true
        )

        XCTAssertEqual(result, preciseBox)
    }

    func testResolvedTokenBoundingBoxFallsBackWhenSubrangePreciseBoxCoversParent() {
        let parentBox = CGRect(x: 0.10, y: 0.40, width: 0.60, height: 0.10)
        let preciseBox = parentBox
        let fallbackBox = CGRect(x: 0.37, y: 0.40, width: 0.24, height: 0.10)

        let result = OCRService.resolvedTokenBoundingBox(
            preciseBox: preciseBox,
            fallbackBox: fallbackBox,
            parentBox: parentBox,
            isSubrange: true
        )

        XCTAssertEqual(result, fallbackBox)
    }

    func testResolvedTokenBoundingBoxFallsBackWhenSubrangePreciseBoxExtendsIntoSuffix() {
        let parentBox = CGRect(x: 0.10, y: 0.40, width: 0.80, height: 0.10)
        let preciseBox = CGRect(x: 0.20, y: 0.40, width: 0.32, height: 0.10)
        let fallbackBox = CGRect(x: 0.20, y: 0.40, width: 0.20, height: 0.10)

        let result = OCRService.resolvedTokenBoundingBox(
            preciseBox: preciseBox,
            fallbackBox: fallbackBox,
            parentBox: parentBox,
            isSubrange: true
        )

        XCTAssertEqual(result, fallbackBox)
    }

    func testResolvedTokenBoundingBoxFallsBackWhenSubrangePreciseBoxExtendsIntoPrefix() {
        let parentBox = CGRect(x: 0.10, y: 0.40, width: 0.80, height: 0.10)
        let preciseBox = CGRect(x: 0.20, y: 0.40, width: 0.32, height: 0.10)
        let fallbackBox = CGRect(x: 0.34, y: 0.40, width: 0.10, height: 0.10)

        let result = OCRService.resolvedTokenBoundingBox(
            preciseBox: preciseBox,
            fallbackBox: fallbackBox,
            parentBox: parentBox,
            isSubrange: true
        )

        XCTAssertEqual(result, fallbackBox)
    }

    func testResolvedTokenBoundingBoxFallsBackWhenSubrangePreciseBoxTargetsDifferentSegment() {
        let parentBox = CGRect(x: 0.10, y: 0.40, width: 0.60, height: 0.10)
        let preciseBox = CGRect(x: 0.10, y: 0.40, width: 0.27, height: 0.10)
        let fallbackBox = CGRect(x: 0.39, y: 0.40, width: 0.27, height: 0.10)

        let result = OCRService.resolvedTokenBoundingBox(
            preciseBox: preciseBox,
            fallbackBox: fallbackBox,
            parentBox: parentBox,
            isSubrange: true
        )

        XCTAssertEqual(result, fallbackBox)
    }

    func testResolvedTokenBoundingBoxKeepsPreciseBoxWhenCharacterFallbackDriftsInMixedScriptLine() {
        let parentBox = CGRect(x: 0.10, y: 0.40, width: 0.80, height: 0.10)
        let preciseBox = CGRect(x: 0.62, y: 0.41, width: 0.08, height: 0.08)
        let fallbackBox = CGRect(x: 0.52, y: 0.40, width: 0.06, height: 0.10)

        let result = OCRService.resolvedTokenBoundingBox(
            preciseBox: preciseBox,
            fallbackBox: fallbackBox,
            parentBox: parentBox,
            isSubrange: true,
            allowsFallbackDrift: true
        )

        XCTAssertEqual(result, preciseBox)
    }

    func testSelectWordUsesPreciseMixedScriptBoxForChineseWord() {
        let parentBox = CGRect(x: 0.10, y: 0.40, width: 0.80, height: 0.10)
        let deploymentBox = OCRService.resolvedTokenBoundingBox(
            preciseBox: CGRect(x: 0.62, y: 0.41, width: 0.08, height: 0.08),
            fallbackBox: CGRect(x: 0.52, y: 0.40, width: 0.06, height: 0.10),
            parentBox: parentBox,
            isSubrange: true,
            allowsFallbackDrift: true
        )

        let words = [
            RecognizedWord(
                text: "是",
                boundingBox: CGRect(x: 0.54, y: 0.40, width: 0.04, height: 0.10)
            ),
            RecognizedWord(
                text: "部署",
                boundingBox: deploymentBox ?? .zero
            ),
        ]

        let selected = OCRService.selectWord(
            from: words,
            normalizedPoint: CGPoint(x: 0.65, y: 0.45)
        )

        XCTAssertEqual(selected?.text, "部署")
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

    func testSelectParagraphWithLanguageCheckFallsBackToChineseLineUnderCursor() {
        let lines = [
            RecognizedTextLine(
                text: "新物料维护",
                boundingBox: CGRect(x: 0.10, y: 0.40, width: 0.20, height: 0.08)
            ),
        ]

        let result = OCRService.selectParagraphWithLanguageCheck(
            from: [],
            lines: lines,
            normalizedPoint: CGPoint(x: 0.18, y: 0.44)
        )

        switch result {
        case .textLine(let line):
            XCTAssertEqual(line.text, "新物料维护")
        case .english, .noText:
            XCTFail("Expected Chinese OCR line under cursor to be selected")
        }
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

    func testListItemExtractsSecondScreenshotBulletItem() {
        let firstLine = RecognizedTextLine(
            text: "• Embedding and rerank models from newly added providers now appear in the gateway and GUIJ",
            boundingBox: CGRect(x: 0.0509, y: 0.7096, width: 0.8663, height: 0.0462)
        )
        let secondLine = RecognizedTextLine(
            text: "• Together Al model catalog now includes embedding and rerank model types.",
            boundingBox: CGRect(x: 0.0509, y: 0.6287, width: 0.7006, height: 0.0462)
        )
        let paragraph = RecognizedParagraph(
            text: "\(firstLine.text)\n\(secondLine.text)",
            lines: [firstLine, secondLine],
            boundingBox: firstLine.boundingBox.union(secondLine.boundingBox)
        )
        let otherColumnLine = RecognizedTextLine(
            text: "• Sidebar item",
            boundingBox: CGRect(x: 0.80, y: 0.6287, width: 0.15, height: 0.0462)
        )

        let items = OCRService.listItems(
            in: paragraph,
            rawLines: paragraph.lines + [otherColumnLine]
        )
        let firstItem = OCRService.listItem(
            at: CGPoint(x: 0.25, y: 0.73),
            among: items
        )
        let secondItem = OCRService.listItem(
            at: CGPoint(x: 0.25, y: 0.65),
            among: items
        )

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(firstItem?.text, firstLine.text)
        XCTAssertEqual(
            secondItem?.text,
            secondLine.text
        )
        XCTAssertEqual(secondItem?.lines, [secondLine])
        XCTAssertEqual(secondItem?.boundingBox, secondLine.boundingBox)
    }

    func testListItemReturnsNilWhenItemCoversEntireParagraph() {
        let line = RecognizedTextLine(
            text: "• Only list item",
            boundingBox: CGRect(x: 0.10, y: 0.70, width: 0.30, height: 0.04)
        )
        let paragraph = RecognizedParagraph(
            text: line.text,
            lines: [line],
            boundingBox: line.boundingBox
        )

        let items = OCRService.listItems(in: paragraph, rawLines: paragraph.lines)
        let item = OCRService.listItem(
            at: CGPoint(x: 0.20, y: 0.72),
            in: paragraph,
            rawLines: paragraph.lines
        )

        XCTAssertTrue(items.isEmpty)
        XCTAssertNil(item)
    }

    func testListItemStrictLineHitWinsOverNearbyItemTolerance() {
        let firstLine = RecognizedTextLine(
            text: "• First item",
            boundingBox: CGRect(x: 0.10, y: 0.716, width: 0.30, height: 0.04)
        )
        let secondLine = RecognizedTextLine(
            text: "• Second item",
            boundingBox: CGRect(x: 0.10, y: 0.672, width: 0.30, height: 0.04)
        )
        let paragraph = RecognizedParagraph(
            text: "\(firstLine.text)\n\(secondLine.text)",
            lines: [firstLine, secondLine],
            boundingBox: firstLine.boundingBox.union(secondLine.boundingBox)
        )

        let item = OCRService.listItem(
            at: CGPoint(x: 0.20, y: 0.71),
            in: paragraph,
            rawLines: paragraph.lines
        )

        XCTAssertEqual(item?.text, "• Second item")
        XCTAssertEqual(item?.boundingBox, secondLine.boundingBox)
    }

    func testListItemDoesNotHitBlankSpaceAfterShortFinalLine() {
        let firstLine = RecognizedTextLine(
            text: "• A long first line that establishes the item width",
            boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.70, height: 0.04)
        )
        let finalLine = RecognizedTextLine(
            text: "tail",
            boundingBox: CGRect(x: 0.15, y: 0.66, width: 0.10, height: 0.04)
        )
        let followingItem = RecognizedTextLine(
            text: "• Following item",
            boundingBox: CGRect(x: 0.10, y: 0.60, width: 0.30, height: 0.04)
        )
        let paragraph = RecognizedParagraph(
            text: [firstLine.text, finalLine.text, followingItem.text].joined(separator: "\n"),
            lines: [firstLine, finalLine, followingItem],
            boundingBox: firstLine.boundingBox
                .union(finalLine.boundingBox)
                .union(followingItem.boundingBox)
        )

        let item = OCRService.listItem(
            at: CGPoint(x: 0.60, y: 0.67),
            in: paragraph,
            rawLines: paragraph.lines
        )

        XCTAssertNil(item)
    }

    func testListItemKeepsIndentedContinuationButDropsFollowingItem() {
        let firstLine = RecognizedTextLine(
            text: "• CLI compatibility: Claude, Gemini, Codex,",
            boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.44, height: 0.04)
        )
        let continuationLine = RecognizedTextLine(
            text: "OpenCode, Qwen, OpenClaw",
            boundingBox: CGRect(x: 0.15, y: 0.66, width: 0.34, height: 0.04)
        )
        let followingItem = RecognizedTextLine(
            text: "• Visual interface combined with command-line power",
            boundingBox: CGRect(x: 0.10, y: 0.60, width: 0.50, height: 0.04)
        )
        let expectedBounds = firstLine.boundingBox.union(continuationLine.boundingBox)
        let paragraph = RecognizedParagraph(
            text: [firstLine.text, continuationLine.text, followingItem.text].joined(separator: "\n"),
            lines: [firstLine, continuationLine, followingItem],
            boundingBox: expectedBounds.union(followingItem.boundingBox)
        )

        let item = OCRService.listItem(
            at: CGPoint(x: 0.22, y: 0.68),
            in: paragraph,
            rawLines: paragraph.lines
        )

        XCTAssertEqual(
            item?.text,
            "• CLI compatibility: Claude, Gemini, Codex,\nOpenCode, Qwen, OpenClaw"
        )
        XCTAssertEqual(item?.lines, [firstLine, continuationLine])
        XCTAssertEqual(item?.boundingBox, expectedBounds)
    }

    func testListItemPairsSeparateBulletWithItsOwnBodyLine() {
        let firstBullet = RecognizedTextLine(
            text: "•",
            boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.01, height: 0.02)
        )
        let firstBody = RecognizedTextLine(
            text: "First item",
            boundingBox: CGRect(x: 0.13, y: 0.72, width: 0.20, height: 0.04)
        )
        let secondBullet = RecognizedTextLine(
            text: "•",
            boundingBox: CGRect(x: 0.10, y: 0.68, width: 0.01, height: 0.02)
        )
        let secondBody = RecognizedTextLine(
            text: "Second item",
            boundingBox: CGRect(x: 0.13, y: 0.68, width: 0.20, height: 0.04)
        )
        let rawLines = [firstBullet, firstBody, secondBullet, secondBody]
        let paragraphs = OCRService.groupParagraphs(from: rawLines)

        XCTAssertEqual(paragraphs.count, 1)
        let item = OCRService.listItem(
            at: CGPoint(x: 0.20, y: 0.70),
            in: paragraphs[0],
            rawLines: rawLines
        )

        XCTAssertEqual(item?.text, "• Second item")
        XCTAssertEqual(
            item?.boundingBox,
            secondBullet.boundingBox.union(secondBody.boundingBox)
        )
    }

    func testListItemRecognizesFullWidthOrderedMarkers() {
        let firstLine = RecognizedTextLine(
            text: "１．第一项",
            boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.18, height: 0.04)
        )
        let secondLine = RecognizedTextLine(
            text: "（２）第二项",
            boundingBox: CGRect(x: 0.10, y: 0.64, width: 0.20, height: 0.04)
        )
        let paragraph = RecognizedParagraph(
            text: "\(firstLine.text)\n\(secondLine.text)",
            lines: [firstLine, secondLine],
            boundingBox: firstLine.boundingBox.union(secondLine.boundingBox)
        )

        let item = OCRService.listItem(
            at: CGPoint(x: 0.18, y: 0.66),
            in: paragraph,
            rawLines: paragraph.lines
        )

        XCTAssertEqual(item?.text, "（２）第二项")
        XCTAssertEqual(item?.lines, [secondLine])
        XCTAssertEqual(item?.boundingBox, secondLine.boundingBox)
    }

    func testListItemReturnsNilForOrdinaryParagraphWithoutMarker() {
        let firstLine = RecognizedTextLine(
            text: "This is an ordinary sentence.",
            boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.38, height: 0.04)
        )
        let secondLine = RecognizedTextLine(
            text: "This is another ordinary sentence.",
            boundingBox: CGRect(x: 0.10, y: 0.64, width: 0.42, height: 0.04)
        )
        let paragraph = RecognizedParagraph(
            text: "\(firstLine.text)\n\(secondLine.text)",
            lines: [firstLine, secondLine],
            boundingBox: firstLine.boundingBox.union(secondLine.boundingBox)
        )

        let item = OCRService.listItem(
            at: CGPoint(x: 0.22, y: 0.66),
            in: paragraph,
            rawLines: paragraph.lines
        )

        XCTAssertNil(item)
    }

    func testListItemReturnsNilOutsideItemSoCallerKeepsManualParagraph() {
        let firstLine = RecognizedTextLine(
            text: "• First item",
            boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.30, height: 0.04)
        )
        let secondLine = RecognizedTextLine(
            text: "• Second item",
            boundingBox: CGRect(x: 0.10, y: 0.60, width: 0.32, height: 0.04)
        )
        let originalText = "\(firstLine.text)\n\(secondLine.text)"
        let paragraph = RecognizedParagraph(
            text: originalText,
            lines: [firstLine, secondLine],
            boundingBox: firstLine.boundingBox.union(secondLine.boundingBox)
        )

        let item = OCRService.listItem(
            at: CGPoint(x: 0.20, y: 0.66),
            in: paragraph,
            rawLines: paragraph.lines
        )

        XCTAssertNil(item)
        XCTAssertEqual(paragraph.text, originalText)
    }
}
