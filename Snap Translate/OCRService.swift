import NaturalLanguage
import Foundation
import NaturalLanguage
import Vision

struct RecognizedWord: Equatable {
    var text: String
    var boundingBox: CGRect
}

final class OCRService {
    func recognizeWords(in image: CGImage, language: String) async throws -> [RecognizedWord] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
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
        var words: [RecognizedWord] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else {
                continue
            }
            let text = candidate.string
            let textBoundingBox = observation.boundingBox
            let refinedRanges = refinedTokenRanges(in: text[...])
            let textCount = text.count
            
            for refinedRange in refinedRanges {
                let substring = text[refinedRange]
                guard containsLetterOrNumber(in: substring) else {
                    continue
                }
                let visionBox = try? candidate.boundingBox(for: refinedRange)
                let boundingBox: CGRect
                if let visionBox, !areBoundingBoxesSimilar(visionBox.boundingBox, textBoundingBox) {
                    boundingBox = visionBox.boundingBox
                } else {
                    guard let splitBox = boundingBoxBySplitting(textBoundingBox, totalCount: textCount, text: text, for: refinedRange) else {
                        continue
                    }
                    boundingBox = splitBox
                }
                words.append(RecognizedWord(text: String(substring), boundingBox: boundingBox))
            }
        }
        return words
    }

    private static let tokenCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'’"))
    private static let letterOrNumberSet = CharacterSet.alphanumerics

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

    private static func boundingBoxBySplitting(_ textBox: CGRect, totalCount: Int, text: String, for range: Range<String.Index>) -> CGRect? {
        guard totalCount > 0 else {
            return nil
        }
        guard range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else {
            return nil
        }
        let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
        let endOffset = text.distance(from: text.startIndex, to: range.upperBound)
        guard endOffset > startOffset, startOffset >= 0, endOffset <= totalCount else {
            return nil
        }
        let startFraction = CGFloat(startOffset) / CGFloat(totalCount)
        let endFraction = CGFloat(endOffset) / CGFloat(totalCount)
        let width = textBox.width * (endFraction - startFraction)
        guard width > 0 else {
            return nil
        }
        let x = textBox.minX + textBox.width * startFraction
        return CGRect(x: x, y: textBox.minY, width: width, height: textBox.height)
    }

    private static func areBoundingBoxesSimilar(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.001) -> Bool {
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

    private static func containsLetterOrNumber(in token: Substring) -> Bool {
        token.unicodeScalars.contains { letterOrNumberSet.contains($0) }
    }
}
