import AppKit

final class WordLookupTextView: NSTextView {
    var onWordDoubleClick: ((String, NSPoint) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        onWordDoubleClick != nil || super.acceptsFirstMouse(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2,
              let onWordDoubleClick,
              let window,
              let range = wordRange(at: convert(event.locationInWindow, from: nil)) else {
            super.mouseDown(with: event)
            return
        }

        let word = (string as NSString).substring(with: range)
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        super.mouseDown(with: event)
        if selectedRange() == range {
            onWordDoubleClick(word, screenPoint)
        }
    }

    func wordRange(at viewPoint: NSPoint) -> NSRange? {
        guard let layoutManager, let textContainer, let textStorage,
              textStorage.length > 0 else { return nil }

        let origin = textContainerOrigin
        let point = NSPoint(x: viewPoint.x - origin.x, y: viewPoint.y - origin.y)
        layoutManager.ensureLayout(for: textContainer)
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }

        // TextKit returns the nearest glyph even in empty space at the end of a line.
        let glyphBounds = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyph, length: 1),
            in: textContainer
        )
        guard glyphBounds.contains(point) else { return nil }

        let index = layoutManager.characterIndex(
            for: point,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        let text = textStorage.mutableString
        guard index < text.length else { return nil }
        let character = text.rangeOfComposedCharacterSequence(at: index)
        guard let hit = text.substring(with: character).first, hit.isLetter || hit.isNumber else { return nil }
        let range = textStorage.doubleClick(at: index)
        return text.substring(with: range).contains(where: \.isLetter) ? range : nil
    }
}
