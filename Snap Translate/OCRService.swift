import CoreText
import Foundation
import Vision

struct RecognizedWord: Equatable {
    var text: String
    var boundingBox: CGRect
}

final class OCRService {
    func recognizeWords(in image: CGImage, language: String) async throws -> [RecognizedWord] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.recognitionLanguages = [language]
            if #available(macOS 13.0, *) {
                request.revision = VNRecognizeTextRequestRevision3
            }
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            guard let observations = request.results else {
                return []
            }
            return OCRService.extractWords(from: observations)
        }.value
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

    // 只包含英语字母，数字和其他符号都作为分隔符
    private static let tokenCharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let letterSet = CharacterSet.letters

    private static func refinedTokenRanges(in token: Substring) -> [Range<String.Index>] {
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
    private static func boundingBoxByCharacterRatio(_ textBox: CGRect, text: String, for range: Range<String.Index>) -> CGRect? {
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
    private static func boundingBoxBySplittingWithCoreText(_ textBox: CGRect, text: String, for range: Range<String.Index>) -> CGRect? {
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
    private static func areBoundingBoxesSimilar(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.02) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.size.width - rhs.size.width) <= tolerance
            && abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    private static func isTokenCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { tokenCharacterSet.contains($0) }
    }


    private static func shouldSplitCamelCase(previous: Character, current: Character, next: Character?) -> Bool {
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

    private static func isUppercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
    }

    private static func isLowercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.lowercaseLetters.contains($0) }
    }

    private static func containsLetter(in token: Substring) -> Bool {
        token.unicodeScalars.contains { letterSet.contains($0) }
    }
}
