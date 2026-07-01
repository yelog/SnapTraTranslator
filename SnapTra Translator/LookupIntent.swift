import CoreGraphics
import Foundation

enum SinglePressLookupIntent: Equatable {
    case ocrWord
    case selectedTextSentence(SelectedTextSnapshot)
}

enum SinglePressLookupRouter {
    private static let selectionHitSlop: CGFloat = 8
    private static let maximumSelectionBoundsArea: CGFloat = 180_000
    private static let maximumSelectionBoundsHeight: CGFloat = 320

    static func resolve(
        mouseLocation: CGPoint,
        isSelectedTextTranslationSupported: Bool,
        isSelectedTextTranslationEnabled: Bool,
        hasAccessibilityPermission: Bool,
        selectionSnapshot: SelectedTextSnapshot?
    ) -> SinglePressLookupIntent {
        guard isSelectedTextTranslationSupported,
              isSelectedTextTranslationEnabled,
              hasAccessibilityPermission,
              let selectionSnapshot else {
            return .ocrWord
        }

        guard selectedTextRejectionReason(
            mouseLocation: mouseLocation,
            selectionSnapshot: selectionSnapshot
        ) == nil else {
            return .ocrWord
        }

        return .selectedTextSentence(selectionSnapshot)
    }

    static func selectedTextRejectionReason(
        mouseLocation: CGPoint,
        selectionSnapshot: SelectedTextSnapshot?
    ) -> String? {
        guard let selectionSnapshot else {
            return "missingSnapshot"
        }

        guard isMeaningfulSelectedText(selectionSnapshot.text) else {
            return "nonMeaningfulText"
        }

        guard selectionSnapshot.source != .clipboard else {
            return nil
        }

        guard !hasKnownSelectedRange(selectionSnapshot.selectedRange) else {
            return nil
        }

        guard let bounds = selectionSnapshot.bounds else {
            return "missingBounds"
        }

        guard isTrustedSelectionBounds(bounds) else {
            return "untrustedBounds"
        }

        let hitRect = bounds.insetBy(dx: -selectionHitSlop, dy: -selectionHitSlop)
        guard hitRect.contains(mouseLocation) else {
            return "mouseOutsideSelection"
        }

        return nil
    }

    private static func isMeaningfulSelectedText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return trimmed.unicodeScalars.contains { scalar in
            guard !CharacterSet.controlCharacters.contains(scalar) else {
                return false
            }

            switch scalar.value {
            case 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0xFFFC:
                return false
            default:
                return true
            }
        }
    }

    private static func hasKnownSelectedRange(_ range: NSRange) -> Bool {
        range.location != NSNotFound && range.length > 0
    }

    private static func isTrustedSelectionBounds(_ bounds: CGRect) -> Bool {
        guard !bounds.isNull,
              !bounds.isEmpty,
              bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width > 0,
              bounds.height > 0 else {
            return false
        }

        guard bounds.height <= maximumSelectionBoundsHeight else {
            return false
        }

        return bounds.width * bounds.height <= maximumSelectionBoundsArea
    }
}
