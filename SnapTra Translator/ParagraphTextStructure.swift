import AppKit
import Foundation

enum ParagraphTextBlockKind: Equatable {
    case plainLine
    case listItem(marker: String)
    case blankLine
}

struct ParagraphTextBlock: Equatable {
    let kind: ParagraphTextBlockKind
    var bodyLines: [String]

    var marker: String? {
        guard case .listItem(let marker) = kind else { return nil }
        return marker
    }

    var bodyText: String {
        var text = ""
        for line in bodyLines {
            let next = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !next.isEmpty else { continue }
            if let last = text.last, let first = next.first {
                if last == "\u{00AD}" {
                    text.removeLast()
                } else if !Self.joinsWithoutSpace(last, first) {
                    text.append(" ")
                }
            }
            text += next
        }
        return text
    }

    private static func joinsWithoutSpace(_ last: Character, _ first: Character) -> Bool {
        // Chinese/Japanese wrap between characters. Korean normally wraps between words.
        func isUnspacedScript(_ character: Character) -> Bool {
            character.unicodeScalars.contains { scalar in
                scalar.properties.isIdeographic
                    || (0x3000...0x30FF).contains(scalar.value)
                    || (0x31F0...0x31FF).contains(scalar.value)
                    || (0xFF61...0xFF9F).contains(scalar.value)
            }
        }
        return isUnspacedScript(last) || isUnspacedScript(first)
            || "([{‘“-/".contains(last) || ",.:;!?)]}’”，。！？；：、".contains(first)
            || "，。！？；：".contains(last)
    }

    var translatableText: String? {
        let text = bodyText
        return text.isEmpty ? nil : text
    }

    var displayText: String {
        switch kind {
        case .plainLine:
            return bodyText
        case .listItem(let marker):
            let text = bodyText
            return text.isEmpty ? marker : "\(marker) \(text)"
        case .blankLine:
            return ""
        }
    }
}

struct ParagraphTextStructure: Equatable {
    let blocks: [ParagraphTextBlock]

    var renderedText: String {
        blocks.map(\.displayText).joined(separator: "\n")
    }

    var translatableTexts: [String] {
        blocks.compactMap(\.translatableText)
    }

    static func fromRecognizedLines(_ lines: [RecognizedTextLine]) -> ParagraphTextStructure {
        var blocks: [ParagraphTextBlock] = []
        var previous: RecognizedTextLine?
        var blockStartX: CGFloat = 0

        for line in lines {
            let block = parseLine(line.text)
            if block.kind == .plainLine, let previousLine = previous, let last = blocks.last,
               isAdjacentTextLine(previous: previousLine, next: line) {
                let continuesBlock: Bool
                switch last.kind {
                case .plainLine:
                    continuesBlock = isProseContinuation(previous: previousLine, next: line)
                case .listItem:
                    let indent = max(0.012, line.boundingBox.height * 0.35)
                    continuesBlock = line.boundingBox.minX > blockStartX + indent
                case .blankLine:
                    continuesBlock = false
                }
                if continuesBlock {
                    blocks[blocks.count - 1].bodyLines += block.bodyLines
                    previous = line
                    continue
                }
            }
            blocks.append(block)
            blockStartX = line.boundingBox.minX
            previous = line
        }
        return ParagraphTextStructure(blocks: blocks)
    }

    static func fromText(_ text: String) -> ParagraphTextStructure {
        let blocks = text.components(separatedBy: "\n").map { parseLine($0) }
        return ParagraphTextStructure(blocks: blocks)
    }

    func applyingTranslations(_ translations: [String]) -> String? {
        let expectedCount = translatableTexts.count
        guard translations.count == expectedCount else {
            return nil
        }

        var translationIndex = 0
        let rebuiltBlocks = blocks.map { block -> ParagraphTextBlock in
            guard block.translatableText != nil else {
                return block
            }

            defer { translationIndex += 1 }
            let translated = translations[translationIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return ParagraphTextBlock(
                kind: block.kind,
                bodyLines: translated.isEmpty ? [] : [translated]
            )
        }

        return ParagraphTextStructure(blocks: rebuiltBlocks).renderedText
    }

    private static func parseLine(_ text: String) -> ParagraphTextBlock {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ParagraphTextBlock(kind: .blankLine, bodyLines: []) }
        if let match = markerMatch(in: text) {
            return ParagraphTextBlock(kind: .listItem(marker: match.marker), bodyLines: [match.body])
        }
        return ParagraphTextBlock(kind: .plainLine, bodyLines: [text])
    }

    private static func isAdjacentTextLine(previous: RecognizedTextLine, next: RecognizedTextLine) -> Bool {
        let first = previous.boundingBox
        let second = next.boundingBox
        let minHeight = min(first.height, second.height)
        guard minHeight > 0, first.midY - second.midY >= minHeight * 0.5,
              max(first.height, second.height) <= minHeight * 1.4 else { return false }
        return OCRService.shouldJoinParagraph(previous: previous, next: next)
    }

    private static func isProseContinuation(previous: RecognizedTextLine, next: RecognizedTextLine) -> Bool {
        let first = previous.boundingBox
        let second = next.boundingBox
        // A new first-line indent starts a paragraph. Centered captions can wrap at both margins.
        let tolerance = max(0.012, first.width * 0.07)
        if second.minX > first.minX + tolerance, abs(first.midX - second.midX) > tolerance {
            return false
        }

        let text = previous.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(":") || text.hasSuffix("：") { return false }
        if first.width < second.width * 0.65 {
            // A short heading or the last line of a paragraph typically leaves a ragged right edge.
            if let last = text.last, ".!?。！？".contains(last) { return false }
            if next.text.first?.isLowercase != true, text.last?.isPunctuation != true { return false }
        }
        return true
    }

    private static func markerMatch(in text: String) -> MarkerMatch? {
        for marker in bulletMarkers {
            guard text.hasPrefix(marker) else { continue }

            let remainder = text.dropFirst(marker.count)
            guard remainder.first?.isWhitespace == true else { continue }

            let body = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            return MarkerMatch(marker: marker, body: body)
        }

        guard let match = orderedMarkerRegex.firstMatch(
            in: text,
            options: [],
            range: NSRange(text.startIndex..., in: text)
        ) else {
            return nil
        }

        guard let markerRange = Range(match.range(at: 1), in: text),
              let bodyRange = Range(match.range(at: 2), in: text) else {
            return nil
        }

        let marker = String(text[markerRange])
        let body = String(text[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        return MarkerMatch(marker: marker, body: body)
    }

    private static let bulletMarkers = [
        "•",
        "·",
        "●",
        "○",
        "▪",
        "-",
        "–",
        "—",
        "*",
    ]

    private static let orderedMarkerRegex = try! NSRegularExpression(
        pattern: #"^((?:\d+|[A-Za-z])[.)])\s+(.+)$"#
    )
}

struct ParagraphTextAttributedStringBuilder {
    static func build(
        text: String,
        font: NSFont,
        textColor: NSColor,
        preferredLineHeight: CGFloat
    ) -> NSAttributedString {
        let structure = ParagraphTextStructure.fromText(text)
        let result = NSMutableAttributedString()

        if structure.blocks.isEmpty {
            return NSAttributedString(
                string: "",
                attributes: baseAttributes(
                    font: font,
                    textColor: textColor,
                    preferredLineHeight: preferredLineHeight
                )
            )
        }

        for (index, block) in structure.blocks.enumerated() {
            let attributes = attributes(
                for: block,
                font: font,
                textColor: textColor,
                preferredLineHeight: preferredLineHeight
            )
            result.append(NSAttributedString(string: block.displayText, attributes: attributes))

            if index < structure.blocks.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }

        return result
    }

    static func paragraphStyle(
        for block: ParagraphTextBlock,
        font: NSFont,
        preferredLineHeight: CGFloat
    ) -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.minimumLineHeight = preferredLineHeight
        paragraphStyle.maximumLineHeight = preferredLineHeight

        if let marker = block.marker {
            let markerWidth = ceil((marker + " ").size(withAttributes: [.font: font]).width)
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.headIndent = markerWidth
        }

        return paragraphStyle
    }

    private static func attributes(
        for block: ParagraphTextBlock,
        font: NSFont,
        textColor: NSColor,
        preferredLineHeight: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle(
                for: block,
                font: font,
                preferredLineHeight: preferredLineHeight
            ),
        ]
    }

    private static func baseAttributes(
        font: NSFont,
        textColor: NSColor,
        preferredLineHeight: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        attributes(
            for: ParagraphTextBlock(kind: .plainLine, bodyLines: []),
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
        )
    }
}

private struct MarkerMatch {
    let marker: String
    let body: String
}
