import CoreGraphics
import Foundation

struct SinglePressLookupRequest: Equatable, Sendable {
    let lookupID: UUID
    let mouseLocation: CGPoint
    let supportsSelectedText: Bool
    let selectedTextEnabled: Bool
    let clipboardFallbackEnabled: Bool
    let hasAccessibilityPermission: Bool

    var executionPolicy: SinglePressLookupExecutionPolicy {
        guard supportsSelectedText,
              selectedTextEnabled,
              hasAccessibilityPermission else {
            return .ocrOnly
        }

        return .selectionFirst(allowsClipboardFallback: clipboardFallbackEnabled)
    }
}

enum SinglePressLookupExecutionPolicy: Equatable, Sendable {
    case ocrOnly
    case selectionFirst(allowsClipboardFallback: Bool)
}
