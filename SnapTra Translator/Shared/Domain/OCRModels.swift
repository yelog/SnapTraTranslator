import CoreGraphics
import Foundation

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
