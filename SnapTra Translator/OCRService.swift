import CoreText
import Foundation
import Vision

struct RecognizedWord: Equatable {
    var text: String
    var boundingBox: CGRect
}

struct RecognizedTextLine: Equatable {
    var text: String
    var boundingBox: CGRect
}

struct RecognizedParagraph: Equatable {
    var text: String
    var lines: [RecognizedTextLine]
    var boundingBox: CGRect
}

final class OCRService {
    func recognizeWords(in image: CGImage, language: String) async throws -> [RecognizedWord] {
        let observations = try await recognizeObservations(in: image, language: language)
        return OCRService.extractWords(from: observations)
    }

    func recognizeParagraphs(in image: CGImage, language: String) async throws -> [RecognizedParagraph] {
        let observations = try await recognizeObservations(in: image, language: language)
        let lines = OCRService.extractLines(from: observations)
        return OCRService.groupParagraphs(from: lines)
    }

    /// Returns both grouped English paragraphs and raw text lines for language detection
    func recognizeParagraphsWithRawLines(in image: CGImage, language: String) async throws -> (
        paragraphs: [RecognizedParagraph],
        lines: [RecognizedTextLine]
    ) {
        let observations = try await recognizeObservations(in: image, language: language)
        let lines = OCRService.extractLines(from: observations)
        let paragraphs = OCRService.groupParagraphs(from: lines)
        return (paragraphs, lines)
    }

    private func recognizeObservations(
        in image: CGImage,
        language: String
    ) async throws -> [VNRecognizedTextObservation] {
        try Task.checkCancellation()

        return try await withThrowingTaskGroup(of: [VNRecognizedTextObservation].self) { group in
            group.addTask(priority: .userInitiated) {
                try Task.checkCancellation()

                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                if #available(macOS 13.0, *) {
                    request.revision = VNRecognizeTextRequestRevision3
                    // Enable automatic language detection to handle mixed-language text
                    // This allows recognizing English words embedded in Chinese/Japanese/Korean text
                    request.automaticallyDetectsLanguage = true
                } else {
                    request.recognitionLanguages = [language]
                }

                let handler = VNImageRequestHandler(cgImage: image)
                try handler.perform([request])
                try Task.checkCancellation()

                return request.results ?? []
            }

            let observations = try await group.next() ?? []
            group.cancelAll()
            return observations
        }
    }

    nonisolated private static func extractWords(from observations: [VNRecognizedTextObservation]) -> [RecognizedWord] {
        #if DEBUG
        print("[OCR] ========== New OCR Result ==========")
        print("[OCR] Total observations: \(observations.count)")
        #endif

        var words: [RecognizedWord] = []
        for (obsIndex, observation) in observations.enumerated() {
            guard let candidate = observation.topCandidates(1).first else {
                continue
            }
            let text = candidate.string
            let textBoundingBox = observation.boundingBox
            let refinedRanges = refinedTokenRanges(in: text[...])

            #if DEBUG
            print("[OCR] Observation \(obsIndex): '\(text)', tokenized into \(refinedRanges.count) parts")
            for (i, range) in refinedRanges.enumerated() {
                print("[OCR]   Token \(i): '\(text[range])'")
            }
            #endif

            // 始终使用字符比例计算边界框，确保稳定性
            // Vision 的 boundingBox(for:) 对自定义分词（CamelCase）支持不稳定
            for refinedRange in refinedRanges {
                let substring = text[refinedRange]
                guard containsLetter(in: substring) else {
                    continue
                }

                guard let boundingBox = boundingBoxByCharacterRatio(textBoundingBox, text: text, for: refinedRange) else {
                    continue
                }

                #if DEBUG
                print("[OCR]   '\(substring)' box: x=\(String(format: "%.4f", boundingBox.minX)), w=\(String(format: "%.4f", boundingBox.width))")
                #endif

                words.append(RecognizedWord(text: String(substring), boundingBox: boundingBox))
            }
        }
        return words
    }

    nonisolated static func extractLines(from observations: [VNRecognizedTextObservation]) -> [RecognizedTextLine] {
        observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }

            return RecognizedTextLine(text: text, boundingBox: observation.boundingBox)
        }
    }

    nonisolated static func groupParagraphs(from lines: [RecognizedTextLine]) -> [RecognizedParagraph] {
        // Step 1: Cluster lines into columns by their left-edge (minX).
        //
        // Multi-column pages (e.g. Twitter) interleave lines from different columns
        // when sorted purely by Y. By grouping lines with similar minX into the same
        // column first, we guarantee that paragraph-merging only considers lines that
        // actually share a horizontal lane — preventing right-sidebar lines from
        // breaking a centre-column paragraph mid-flow.
        //
        // Column tolerance: lines whose minX differs by less than `columnTolerance`
        // belong to the same column. We use 0.08 (8 % of normalised width) which is
        // wide enough to tolerate a small paragraph indent but narrow enough to
        // separate a typical three-column web layout.
        let columnTolerance: CGFloat = 0.08

        var columnBuckets: [(representativeX: CGFloat, lines: [RecognizedTextLine])] = []

        for line in lines {
            guard containsLikelyParagraphContent(line.text) else { continue }

            let x = line.boundingBox.minX
            if let idx = columnBuckets.firstIndex(where: { abs($0.representativeX - x) <= columnTolerance }) {
                columnBuckets[idx].lines.append(line)
            } else {
                columnBuckets.append((representativeX: x, lines: [line]))
            }
        }

        // Step 2: Within each column, sort lines top-to-bottom and merge into paragraphs.
        var allParagraphs: [RecognizedParagraph] = []

        for bucket in columnBuckets {
            let sortedLines = bucket.lines.sorted { lhs, rhs in
                // Primary: top-to-bottom (higher midY = higher on screen in Vision coords)
                if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.005 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }

            var grouped: [[RecognizedTextLine]] = []

            for line in sortedLines {
                if var lastGroup = grouped.last,
                   let lastLine = lastGroup.last {
                    if shouldJoinParagraph(previous: lastLine, next: line) {
                        lastGroup.append(line)
                        grouped[grouped.count - 1] = lastGroup
                    } else {
                        grouped.append([line])
                    }
                } else {
                    grouped.append([line])
                }
            }

            let paragraphs: [RecognizedParagraph] = grouped.compactMap { groupLines in
                guard let firstLine = groupLines.first else { return nil }
                let text = normalizedParagraphText(from: groupLines)
                guard isLikelyEnglishParagraph(text) else { return nil }

                let boundingBox = groupLines.dropFirst().reduce(firstLine.boundingBox) { acc, l in
                    acc.union(l.boundingBox)
                }
                return RecognizedParagraph(text: text, lines: groupLines, boundingBox: boundingBox)
            }

            allParagraphs.append(contentsOf: paragraphs)
        }

        return allParagraphs
    }

    nonisolated static func selectParagraph(
        from paragraphs: [RecognizedParagraph],
        normalizedPoint: CGPoint
    ) -> RecognizedParagraph? {
        let tolerance: CGFloat = 0.01
        let containing = paragraphs.filter { paragraph in
            paragraph.boundingBox.insetBy(dx: -tolerance, dy: -tolerance).contains(normalizedPoint)
        }

        if !containing.isEmpty {
            return containing.min { lhs, rhs in
                let lhsDistance = hypot(lhs.boundingBox.midX - normalizedPoint.x, lhs.boundingBox.midY - normalizedPoint.y)
                let rhsDistance = hypot(rhs.boundingBox.midX - normalizedPoint.x, rhs.boundingBox.midY - normalizedPoint.y)
                return lhsDistance < rhsDistance
            }
        }

        let maxDistance: CGFloat = 0.18
        return paragraphs
            .compactMap { paragraph -> (RecognizedParagraph, CGFloat)? in
                let distance = hypot(paragraph.boundingBox.midX - normalizedPoint.x, paragraph.boundingBox.midY - normalizedPoint.y)
                guard distance <= maxDistance else { return nil }
                return (paragraph, distance)
            }
            .min(by: { lhs, rhs in lhs.1 < rhs.1 })?
            .0
    }

    /// Result type for paragraph selection with language detection
    enum ParagraphSelectionResult {
        /// Found an English paragraph at the cursor position
        case english(RecognizedParagraph)
        /// Cursor is on non-English content (Chinese, etc.)
        case nonEnglish
        /// No text found at cursor position
        case noText
    }

    /// Selects paragraph with language-aware detection.
    /// First checks if cursor is on any text (including Chinese), then determines if it's English.
    nonisolated static func selectParagraphWithLanguageCheck(
        from paragraphs: [RecognizedParagraph],
        lines: [RecognizedTextLine],
        normalizedPoint: CGPoint
    ) -> ParagraphSelectionResult {
        let tolerance: CGFloat = 0.01

        // Phase 1: Check if cursor is on any text line (including non-English)
        let containingLines = lines.filter { line in
            line.boundingBox.insetBy(dx: -tolerance, dy: -tolerance).contains(normalizedPoint)
        }

        if !containingLines.isEmpty {
            // Cursor is on some text - check if it's an English paragraph
            if let englishParagraph = paragraphs.first(where: { paragraph in
                paragraph.boundingBox.insetBy(dx: -tolerance, dy: -tolerance).contains(normalizedPoint)
            }) {
                // Cursor is on English paragraph
                return .english(englishParagraph)
            } else {
                // Cursor is on non-English text (Chinese, etc.)
                return .nonEnglish
            }
        }

        // Phase 2: Cursor is not on any text - find nearest English paragraph with reduced search radius
        let maxDistance: CGFloat = 0.08  // Reduced from 0.18 to avoid selecting distant paragraphs
        let closestParagraph = paragraphs
            .compactMap { paragraph -> (RecognizedParagraph, CGFloat)? in
                let distance = hypot(
                    paragraph.boundingBox.midX - normalizedPoint.x,
                    paragraph.boundingBox.midY - normalizedPoint.y
                )
                guard distance <= maxDistance else { return nil }
                return (paragraph, distance)
            }
            .min(by: { $0.1 < $1.1 })?
            .0

        if let paragraph = closestParagraph {
            return .english(paragraph)
        }

        return .noText
    }

    // 只包含英语字母，数字和其他符号都作为分隔符
    nonisolated private static let tokenCharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    nonisolated private static let letterSet = CharacterSet.letters

    nonisolated private static func refinedTokenRanges(in token: Substring) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        let indices = Array(token.indices)
        var tokenStart: String.Index?
        var previousCharacter: Character?

        for (position, index) in indices.enumerated() {
            let currentCharacter = token[index]
            let nextCharacter = position + 1 < indices.count ? token[indices[position + 1]] : nil

            if isTokenCharacter(currentCharacter) {
                if tokenStart == nil {
                    tokenStart = index
                } else if let previousCharacter, shouldSplitCamelCase(previous: previousCharacter, current: currentCharacter, next: nextCharacter) {
                    if let start = tokenStart {
                        ranges.append(start..<index)
                    }
                    tokenStart = index
                }
                previousCharacter = currentCharacter
            } else {
                if let start = tokenStart {
                    ranges.append(start..<index)
                    tokenStart = nil
                }
                previousCharacter = nil
            }
        }

        if let start = tokenStart {
            ranges.append(start..<token.endIndex)
        }

        return ranges
    }

    // 使用简单的字符比例计算边界框（最稳定的方法）
    nonisolated private static func boundingBoxByCharacterRatio(_ textBox: CGRect, text: String, for range: Range<String.Index>) -> CGRect? {
        let totalCount = text.count
        guard totalCount > 0 else { return nil }
        guard range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else { return nil }

        let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
        let endOffset = text.distance(from: text.startIndex, to: range.upperBound)

        guard endOffset > startOffset else { return nil }

        let startFraction = CGFloat(startOffset) / CGFloat(totalCount)
        let endFraction = CGFloat(endOffset) / CGFloat(totalCount)

        let x = textBox.minX + textBox.width * startFraction
        let width = textBox.width * (endFraction - startFraction)

        guard width > 0 else { return nil }

        return CGRect(x: x, y: textBox.minY, width: width, height: textBox.height)
    }

    // 使用 Core Text 测量实际字符宽度来计算边界框（备用方法）
    nonisolated private static func boundingBoxBySplittingWithCoreText(_ textBox: CGRect, text: String, for range: Range<String.Index>) -> CGRect? {
        guard range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else {
            return nil
        }

        // 使用系统字体来估算字符宽度
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font]

        // 计算整个字符串的宽度
        let fullAttrString = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        let fullLine = CTLineCreateWithAttributedString(fullAttrString)
        let fullWidth = CTLineGetTypographicBounds(fullLine, nil, nil, nil)

        guard fullWidth > 0 else { return nil }

        // 计算前缀字符串的宽度
        let prefixRange = text.startIndex..<range.lowerBound
        let prefixString = String(text[prefixRange])
        var prefixWidth: Double = 0
        if !prefixString.isEmpty {
            let prefixAttrString = CFAttributedStringCreate(nil, prefixString as CFString, attributes as CFDictionary)!
            let prefixLine = CTLineCreateWithAttributedString(prefixAttrString)
            prefixWidth = CTLineGetTypographicBounds(prefixLine, nil, nil, nil)
        }

        // 计算目标子串的宽度
        let substring = String(text[range])
        let subAttrString = CFAttributedStringCreate(nil, substring as CFString, attributes as CFDictionary)!
        let subLine = CTLineCreateWithAttributedString(subAttrString)
        let subWidth = CTLineGetTypographicBounds(subLine, nil, nil, nil)

        guard subWidth > 0 else { return nil }

        let startFraction = CGFloat(prefixWidth / fullWidth)
        let widthFraction = CGFloat(subWidth / fullWidth)

        let x = textBox.minX + textBox.width * startFraction
        let width = textBox.width * widthFraction

        return CGRect(x: x, y: textBox.minY, width: width, height: textBox.height)
    }

    // 检查两个边界框是否相似（用于判断 Vision 是否返回了精确的子范围边界框）
    nonisolated private static func areBoundingBoxesSimilar(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.02) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.size.width - rhs.size.width) <= tolerance
            && abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    nonisolated private static func isTokenCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { tokenCharacterSet.contains($0) }
    }


    nonisolated private static func shouldSplitCamelCase(previous: Character, current: Character, next: Character?) -> Bool {
        let previousIsLowercase = isLowercaseLetter(previous)
        let previousIsUppercase = isUppercaseLetter(previous)
        let currentIsUppercase = isUppercaseLetter(current)
        let nextIsLowercase = next.map(isLowercaseLetter) ?? false

        if previousIsLowercase && currentIsUppercase {
            return true
        }

        if previousIsUppercase && currentIsUppercase && nextIsLowercase {
            return true
        }

        return false
    }

    nonisolated private static func isUppercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
    }

    nonisolated private static func isLowercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.lowercaseLetters.contains($0) }
    }

    nonisolated private static func containsLetter(in token: Substring) -> Bool {
        token.unicodeScalars.contains { letterSet.contains($0) }
    }

    nonisolated private static func shouldJoinParagraph(
        previous: RecognizedTextLine,
        next: RecognizedTextLine
    ) -> Bool {
        let previousHeight = previous.boundingBox.height
        let nextHeight = next.boundingBox.height
        let minHeight = min(previousHeight, nextHeight)
        let maxHeight = max(previousHeight, nextHeight)
        guard minHeight > 0 else { return false }

        // Lines with very different heights are likely different elements (e.g. heading vs body).
        // However, a bold line followed by regular body text can have heightRatio up to ~1.6
        // because bold glyphs occupy more vertical space in Vision's bounding box.
        // True heading+body pairs are distinguished by a larger vertical gap, so we relax
        // the height gate to 2.0 and rely on the vertical gap check to prevent mis-merges.
        let heightRatio = maxHeight / minHeight
        guard heightRatio <= 2.0 else { return false }

        // Vertical gap must be within normal line-spacing range.
        // When heightRatio is large (e.g. bold line before normal body), tighten the gap
        // threshold to avoid merging a true heading with the paragraph below it.
        let verticalGap = max(previous.boundingBox.minY - next.boundingBox.maxY, 0)
        let gapThreshold: CGFloat = heightRatio > 1.4 ? maxHeight * 0.5 : maxHeight * 0.8
        guard verticalGap <= gapThreshold else { return false }

        // Require meaningful horizontal overlap OR left-edge alignment to join lines.
        //
        // Pure overlap check fails for paragraph lines that wrap differently due to
        // an adjacent column or sidebar occluding part of the line — Vision may assign
        // different right-edge extents to each line, yielding zero overlap even though
        // the lines share the same left margin and clearly belong to the same paragraph.
        //
        // Strategy:
        //   1. If horizontal overlap ≥ 25 % of the shorter line → join (original rule).
        //   2. Otherwise, if both lines' left edges are within 2× line-height of each
        //      other AND the shorter line's right edge does not extend clearly to the
        //      left of the longer line's start → treat as left-aligned continuation.
        let prevMinX = previous.boundingBox.minX
        let prevMaxX = previous.boundingBox.maxX
        let nextMinX = next.boundingBox.minX
        let nextMaxX = next.boundingBox.maxX
        let overlapWidth = max(0, min(prevMaxX, nextMaxX) - max(prevMinX, nextMinX))
        let minWidth = min(previous.boundingBox.width, next.boundingBox.width)
        let horizontalOverlapRatio = minWidth > 0 ? overlapWidth / minWidth : 0

        if horizontalOverlapRatio >= 0.25 {
            return true
        }

        // Left-alignment fallback: lines share a left margin (within 2× line height)
        // and neither line starts significantly to the right of the other's left edge.
        let leftEdgeDelta = abs(prevMinX - nextMinX)
        let leftAlignThreshold = maxHeight * 2.0
        let leftAligned = leftEdgeDelta <= leftAlignThreshold

        // Reject if the lines are clearly side-by-side (right edge of one line is to
        // the left of the start of the other line by more than a small tolerance).
        let sideBySide = (prevMaxX + maxHeight < nextMinX) || (nextMaxX + maxHeight < prevMinX)

        return leftAligned && !sideBySide
    }

    nonisolated private static func normalizedParagraphText(from lines: [RecognizedTextLine]) -> String {
        lines
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func containsLikelyParagraphContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { letterSet.contains($0) || $0.properties.isIdeographic }
    }

    nonisolated private static func isLikelyEnglishParagraph(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { letterSet.contains($0) }
        guard letters.count >= 12 else {
            return false
        }

        let englishLetters = text.unicodeScalars.filter { tokenCharacterSet.contains($0) }
        guard !letters.isEmpty else {
            return false
        }

        let englishRatio = Double(englishLetters.count) / Double(letters.count)
        let words = text.split(whereSeparator: \.isWhitespace).filter { token in
            token.unicodeScalars.contains { tokenCharacterSet.contains($0) }
        }

        return englishRatio >= 0.65 && words.count >= 3
    }

    /// Estimates the display font size for a paragraph based on its line heights
    nonisolated static func estimatedDisplayFontSize(for paragraph: RecognizedParagraph, in captureRect: CGRect) -> CGFloat {
        guard !paragraph.lines.isEmpty else {
            return 14.0 // Default fallback
        }

        // Calculate average line height in normalized coordinates
        let avgNormalizedHeight = paragraph.lines.map { $0.boundingBox.height }.reduce(0, +) / CGFloat(paragraph.lines.count)

        // Convert to screen coordinates
        let screenHeight = avgNormalizedHeight * captureRect.height

        // Font size is typically ~0.7-0.8 of line height
        return screenHeight * 0.75
    }
}
