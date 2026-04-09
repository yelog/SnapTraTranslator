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

        return .selectedTextSentence(selectionSnapshot)
    }
}
