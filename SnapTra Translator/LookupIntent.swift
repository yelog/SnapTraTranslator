import CoreGraphics
import Foundation

enum SinglePressLookupIntent: Equatable {
    case ocrWord
    case selectedTextSentence(SelectedTextSnapshot)
}

enum SinglePressLookupRouter {
    static func resolve(
        mouseLocation: CGPoint,
        isSelectedTextTranslationEnabled: Bool,
        hasAccessibilityPermission: Bool,
        selectionSnapshot: SelectedTextSnapshot?
    ) -> SinglePressLookupIntent {
        guard isSelectedTextTranslationEnabled,
              hasAccessibilityPermission,
              let selectionSnapshot,
              isPointer(mouseLocation, inside: selectionSnapshot.bounds) else {
            return .ocrWord
        }

        return .selectedTextSentence(selectionSnapshot)
    }

    static func isPointer(_ point: CGPoint, inside bounds: CGRect) -> Bool {
        bounds.insetBy(dx: -2, dy: -2).contains(point)
    }
}
