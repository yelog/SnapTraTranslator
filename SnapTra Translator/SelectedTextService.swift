import AppKit
import ApplicationServices
import Foundation

struct SelectedTextSnapshot: Equatable {
    let text: String
    let selectedRange: NSRange
    let bounds: CGRect
    let sourceAppIdentifier: String?
}

final class SelectedTextService {
    func currentSelectionSnapshot() -> SelectedTextSnapshot? {
        let systemWideElement = AXUIElementCreateSystemWide()

        guard let focusedElement = focusedElement(from: systemWideElement),
              let text = selectedText(from: focusedElement),
              let rangeResult = selectedRange(from: focusedElement),
              let bounds = bounds(for: rangeResult.axValue, in: focusedElement) else {
            return nil
        }

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty, bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        return SelectedTextSnapshot(
            text: normalizedText,
            selectedRange: rangeResult.range,
            bounds: normalizedScreenRect(for: bounds),
            sourceAppIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
    }

    private func focusedElement(from systemWideElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func selectedText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )
        guard result == .success else {
            return nil
        }
        return value as? String
    }

    private func selectedRange(from element: AXUIElement) -> (range: NSRange, axValue: AXValue)? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var cfRange = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &cfRange), cfRange.length > 0 else {
            return nil
        }

        return (
            NSRange(location: cfRange.location, length: cfRange.length),
            axValue
        )
    }

    private func bounds(for rangeValue: AXValue, in element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        guard result == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
            return nil
        }

        return rect
    }

    private func normalizedScreenRect(for rect: CGRect) -> CGRect {
        guard let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() else {
            return rect
        }

        return CGRect(
            x: rect.minX,
            y: globalMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
