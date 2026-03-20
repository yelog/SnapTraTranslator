import AppKit
import Foundation

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
