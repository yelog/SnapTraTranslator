import CoreGraphics
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
        bodyLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
        let sourceLines = lines.map {
            SourceLine(
                text: $0.text,
                leadingX: $0.boundingBox.minX,
                lineHeight: $0.boundingBox.height
            )
        }
        return ParagraphTextStructure(blocks: parseRecognizedLines(sourceLines))
    }

    static func fromText(_ text: String) -> ParagraphTextStructure {
        let sourceLines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { SourceLine(text: String($0), leadingX: nil, lineHeight: nil) }
        return ParagraphTextStructure(blocks: parsePlainTextLines(sourceLines))
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

    private static func parseRecognizedLines(_ lines: [SourceLine]) -> [ParagraphTextBlock] {
        var pendingBlocks: [PendingBlock] = []

        for line in lines {
            let trimmedText = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                pendingBlocks.append(PendingBlock(block: ParagraphTextBlock(kind: .blankLine, bodyLines: [])))
                continue
            }

            if let markerMatch = markerMatch(in: trimmedText) {
                pendingBlocks.append(
                    PendingBlock(
                        block: ParagraphTextBlock(
                            kind: .listItem(marker: markerMatch.marker),
                            bodyLines: [markerMatch.body]
                        ),
                        markerLeadingX: line.leadingX,
                        markerLineHeight: line.lineHeight
                    )
                )
                continue
            }

            if let index = pendingBlocks.indices.last,
               pendingBlocks[index].block.marker != nil,
               shouldAppendToPreviousListItem(
                currentLeadingX: line.leadingX,
                currentLineHeight: line.lineHeight,
                previous: pendingBlocks[index]
               ) {
                pendingBlocks[index].block.bodyLines.append(trimmedText)
                continue
            }

            pendingBlocks.append(
                PendingBlock(
                    block: ParagraphTextBlock(kind: .plainLine, bodyLines: [trimmedText])
                )
            )
        }

        return pendingBlocks.map(\.block)
    }

    private static func parsePlainTextLines(_ lines: [SourceLine]) -> [ParagraphTextBlock] {
        lines.map { line in
            let trimmedText = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                return ParagraphTextBlock(kind: .blankLine, bodyLines: [])
            }

            if let markerMatch = markerMatch(in: trimmedText) {
                return ParagraphTextBlock(
                    kind: .listItem(marker: markerMatch.marker),
                    bodyLines: [markerMatch.body]
                )
            }

            return ParagraphTextBlock(kind: .plainLine, bodyLines: [trimmedText])
        }
    }

    private static func shouldAppendToPreviousListItem(
        currentLeadingX: CGFloat?,
        currentLineHeight: CGFloat?,
        previous: PendingBlock
    ) -> Bool {
        guard let currentLeadingX,
              let markerLeadingX = previous.markerLeadingX else {
            return false
        }

        let lineHeight = max(previous.markerLineHeight ?? 0, currentLineHeight ?? 0)
        let indentThreshold = max(lineHeight * 0.35, 0.012)
        return currentLeadingX > markerLeadingX + indentThreshold
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

private struct SourceLine {
    let text: String
    let leadingX: CGFloat?
    let lineHeight: CGFloat?
}

private struct PendingBlock {
    var block: ParagraphTextBlock
    var markerLeadingX: CGFloat? = nil
    var markerLineHeight: CGFloat? = nil
}

private struct MarkerMatch {
    let marker: String
    let body: String
}
