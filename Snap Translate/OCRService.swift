import NaturalLanguage
import Foundation
import NaturalLanguage
import Vision

struct RecognizedWord: Equatable {
    var text: String
    var boundingBox: CGRect
}

final class OCRService {
    func recognizeWords(in image: CGImage) async throws -> [RecognizedWord] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if #available(macOS 13.0, *) {
                request.revision = VNRecognizeTextRequestRevision3
                request.automaticallyDetectsLanguage = true
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
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = candidate.string
            tokenizer.enumerateTokens(in: candidate.string.startIndex..<candidate.string.endIndex) { range, _ in
                let token = candidate.string[range]
                let refinedRanges = refinedTokenRanges(in: token)
                let tokenBoundingObservation = try? candidate.boundingBox(for: range)
                for refinedRange in refinedRanges {
                    let substring = candidate.string[refinedRange]
                    guard containsLetterOrNumber(in: substring) else {
                        continue
                    }
                    let refinedObservation = try? candidate.boundingBox(for: refinedRange)
                    if let boundingBox = refinedBoundingBox(
                        refinedObservation: refinedObservation,
                        tokenObservation: tokenBoundingObservation,
                        token: token,
                        refinedRange: refinedRange,
                        hasMultipleRanges: refinedRanges.count > 1
                    ) {
                        words.append(RecognizedWord(text: String(substring), boundingBox: boundingBox))
                    }
                }
                return true
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

    private static func refinedBoundingBox(
        refinedObservation: VNRectangleObservation?,
        tokenObservation: VNRectangleObservation?,
        token: Substring,
        refinedRange: Range<String.Index>,
        hasMultipleRanges: Bool
    ) -> CGRect? {
        if let refinedObservation {
            if !hasMultipleRanges {
                return refinedObservation.boundingBox
            }
            if let tokenObservation, !areBoundingBoxesSimilar(refinedObservation.boundingBox, tokenObservation.boundingBox) {
                return refinedObservation.boundingBox
            }
        }
        guard hasMultipleRanges, let tokenObservation else {
            return refinedObservation?.boundingBox
        }
        return boundingBoxBySplitting(tokenObservation.boundingBox, in: token, for: refinedRange)
    }

    private static func boundingBoxBySplitting(_ tokenBox: CGRect, in token: Substring, for range: Range<String.Index>) -> CGRect? {
        let tokenCount = token.count
        guard tokenCount > 0 else {
            return nil
        }
        let startOffset = token.distance(from: token.startIndex, to: range.lowerBound)
        let endOffset = token.distance(from: token.startIndex, to: range.upperBound)
        guard endOffset > startOffset else {
            return nil
        }
        let startFraction = CGFloat(startOffset) / CGFloat(tokenCount)
        let endFraction = CGFloat(endOffset) / CGFloat(tokenCount)
        let width = tokenBox.width * (endFraction - startFraction)
        guard width > 0 else {
            return nil
        }
        let x = tokenBox.minX + tokenBox.width * startFraction
        return CGRect(x: x, y: tokenBox.minY, width: width, height: tokenBox.height)
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
