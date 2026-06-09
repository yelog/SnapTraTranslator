import CoreGraphics
import Foundation

enum SinglePressLookupIntent: Equatable {
    case ocrWord
    case selectedTextSentence(SelectedTextSnapshot)
}

enum SinglePressLookupRouter {
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
        _ = mouseLocation

        guard let selectionSnapshot else {
            return "missingSnapshot"
        }

        guard isMeaningfulSelectedText(selectionSnapshot.text) else {
            return "nonMeaningfulText"
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
}
