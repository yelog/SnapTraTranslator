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
                let word = String(candidate.string[range])
                if let box = try? candidate.boundingBox(for: range) {
                    words.append(RecognizedWord(text: word, boundingBox: box.boundingBox))
                }
                return true
            }
        }
        return words
    }
}
