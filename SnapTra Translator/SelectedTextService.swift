import AppKit
import ApplicationServices
import Foundation

struct SelectedTextSnapshot: Equatable {
    let text: String
    let selectedRange: NSRange
    let bounds: CGRect?
    let sourceAppIdentifier: String?
}

final class SelectedTextService {
    private struct CandidateElement {
        let element: AXUIElement
        let source: String
        let depth: Int
    }

    func currentSelectionSnapshot(mouseLocation: CGPoint) -> SelectedTextSnapshot? {
        let systemWideElement = AXUIElementCreateSystemWide()
        configureMessagingTimeout(for: systemWideElement)

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let sourceAppIdentifier = frontmostApplication?.bundleIdentifier
        let frontmostAppElement = frontmostApplication.map { applicationElement(for: $0) }
        if let frontmostAppElement {
            configureMessagingTimeout(for: frontmostAppElement)
        }

        let candidates = candidateElements(
            from: systemWideElement,
            frontmostAppElement: frontmostAppElement,
            mouseLocation: mouseLocation
        )

        debugLog(
            "start mouse=\(describe(point: mouseLocation)) frontmostApp=\(sourceAppIdentifier ?? "nil") candidates=\(candidates.count)"
        )

        for (index, candidate) in candidates.enumerated() {
            let context = "candidate[\(index)] \(candidate.source)#\(candidate.depth)"
            debugLog("\(context) \(debugSummary(of: candidate.element))")
            if let snapshot = snapshot(
                from: candidate.element,
                sourceAppIdentifier: sourceAppIdentifier,
                debugContext: context
            ) {
                debugLog(
                    "\(context) success text=\"\(truncate(snapshot.text))\" bounds=\(snapshot.bounds.map { describe(rect: $0) } ?? "nil")"
                )
                return snapshot
            }
            debugLog("\(context) no usable snapshot")
        }

        debugLog("no selection snapshot")
        return nil
    }

    private func candidateElements(
        from systemWideElement: AXUIElement,
        frontmostAppElement: AXUIElement?,
        mouseLocation: CGPoint
    ) -> [CandidateElement] {
        var elements: [CandidateElement] = []

        if let frontmostAppElement,
           let hoveredElement = element(at: mouseLocation, from: frontmostAppElement, source: "frontmostApp") {
            appendUnique(
                elementChain(startingFrom: hoveredElement, source: "frontmostApp-hovered"),
                to: &elements
            )
        }

        if let hoveredElement = element(at: mouseLocation, from: systemWideElement, source: "systemWide") {
            appendUnique(
                elementChain(startingFrom: hoveredElement, source: "systemWide-hovered"),
                to: &elements
            )
        }

        if let frontmostAppElement,
           let focusedElement = focusedElement(from: frontmostAppElement, source: "frontmostApp") {
            appendUnique(
                elementChain(startingFrom: focusedElement, source: "frontmostApp-focusedElement"),
                to: &elements
            )
        }

        if let frontmostAppElement,
           let focusedWindow = focusedWindow(from: frontmostAppElement) {
            appendUnique(
                elementChain(startingFrom: focusedWindow, source: "frontmostApp-focusedWindow"),
                to: &elements
            )
        }

        if let focusedApplication = focusedApplication(from: systemWideElement) {
            appendUnique(
                elementChain(startingFrom: focusedApplication, source: "systemWide-focusedApplication"),
                to: &elements
            )
        }

        if let focusedElement = focusedElement(from: systemWideElement, source: "systemWide") {
            appendUnique(
                elementChain(startingFrom: focusedElement, source: "systemWide-focusedElement"),
                to: &elements
            )
        }

        return elements
    }

    private func snapshot(
        from element: AXUIElement,
        sourceAppIdentifier: String?,
        debugContext: String
    ) -> SelectedTextSnapshot? {
        let directText = selectedText(from: element, debugContext: debugContext)
        let rangeResult = selectedRange(from: element, debugContext: debugContext)
        let markerRange = selectedTextMarkerRange(from: element, debugContext: debugContext)
        let rangeText = rangeResult.flatMap { string(for: $0.axValue, in: element, debugContext: debugContext) }
        let markerText = markerRange.flatMap {
            string(forTextMarkerRange: $0, in: element, debugContext: debugContext)
        }
        let markerAttributedText = markerRange.flatMap {
            attributedString(forTextMarkerRange: $0, in: element, debugContext: debugContext)?.string
        }

        debugLog(
            "\(debugContext) directText=\(directText != nil) range=\(describe(range: rangeResult?.range)) markerRange=\(markerRange != nil)"
        )

        guard let text = directText
            ?? rangeText
            ?? markerText
            ?? markerAttributedText else {
            debugLog("\(debugContext) no selected text value")
            return nil
        }

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            debugLog("\(debugContext) selected text empty after trim")
            return nil
        }

        debugLog("\(debugContext) resolved text=\"\(truncate(normalizedText))\"")

        let selectedRange = rangeResult?.range ?? NSRange(location: NSNotFound, length: normalizedText.utf16.count)

        // Try to obtain bounds via AXBoundsForRange first, then AXBoundsForTextMarkerRange.
        var resolvedBounds: CGRect?

        if let rangeResult,
           let rawBounds = bounds(for: rangeResult.axValue, in: element, debugContext: debugContext) {
            let normalized = normalizedScreenRect(for: rawBounds)
            if normalized.width > 0, normalized.height > 0 {
                resolvedBounds = normalized
                debugLog("\(debugContext) using range bounds raw=\(describe(rect: rawBounds)) normalized=\(describe(rect: normalized))")
            }
        }

        if resolvedBounds == nil, let markerRange,
           let rawBounds = bounds(forTextMarkerRange: markerRange, in: element, debugContext: debugContext) {
            let normalized = normalizedScreenRect(for: rawBounds)
            if normalized.width > 0, normalized.height > 0 {
                resolvedBounds = normalized
                debugLog("\(debugContext) using marker bounds raw=\(describe(rect: rawBounds)) normalized=\(describe(rect: normalized))")
            }
        }

        if resolvedBounds == nil {
            debugLog("\(debugContext) no usable bounds, creating snapshot without bounds")
        }

        return SelectedTextSnapshot(
            text: normalizedText,
            selectedRange: selectedRange,
            bounds: resolvedBounds,
            sourceAppIdentifier: sourceAppIdentifier
        )
    }

    private func focusedElement(from systemWideElement: AXUIElement) -> AXUIElement? {
        focusedElement(from: systemWideElement, source: nil)
    }

    private func focusedElement(from element: AXUIElement, source: String?) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            if let source {
                debugLog("\(source) AXFocusedUIElement error=\(String(describing: result))")
            }
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            if let source {
                debugLog("\(source) AXFocusedUIElement unexpected type")
            }
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func focusedApplication(from systemWideElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            debugLog("systemWide AXFocusedApplication error=\(String(describing: result))")
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            debugLog("systemWide AXFocusedApplication unexpected type")
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func focusedWindow(from applicationElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            debugLog("frontmostApp AXFocusedWindow error=\(String(describing: result))")
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            debugLog("frontmostApp AXFocusedWindow unexpected type")
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func applicationElement(for application: NSRunningApplication) -> AXUIElement {
        AXUIElementCreateApplication(application.processIdentifier)
    }

    private func element(at mouseLocation: CGPoint, from rootElement: AXUIElement, source: String) -> AXUIElement? {
        let accessibilityPoint = accessibilityPoint(for: mouseLocation)
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            rootElement,
            Float(accessibilityPoint.x),
            Float(accessibilityPoint.y),
            &element
        )
        guard result == .success else {
            debugLog(
                "\(source) hovered element lookup failed mouse=\(describe(point: mouseLocation)) axPoint=\(describe(point: accessibilityPoint)) error=\(String(describing: result))"
            )
            return nil
        }
        return element
    }

    private func elementChain(
        startingFrom element: AXUIElement,
        source: String,
        maxDepth: Int = 8
    ) -> [CandidateElement] {
        var chain: [CandidateElement] = []
        var current: AXUIElement? = element

        for depth in 0..<maxDepth {
            guard let currentElement = current else { break }
            chain.append(
                CandidateElement(
                    element: currentElement,
                    source: source,
                    depth: depth
                )
            )
            current = parent(of: currentElement)
        }

        return chain
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
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

    private func selectedText(from element: AXUIElement, debugContext: String? = nil) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )
        guard result == .success else {
            if let debugContext {
                debugLog("\(debugContext) AXSelectedText error=\(String(describing: result))")
            }
            return nil
        }
        return value as? String
    }

    private func selectedRange(from element: AXUIElement, debugContext: String? = nil) -> (range: NSRange, axValue: AXValue)? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            if let debugContext {
                debugLog("\(debugContext) AXSelectedTextRange error=\(String(describing: result))")
            }
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            if let debugContext {
                debugLog("\(debugContext) AXSelectedTextRange unexpected type")
            }
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            if let debugContext {
                debugLog("\(debugContext) AXSelectedTextRange not cfRange")
            }
            return nil
        }

        var cfRange = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &cfRange), cfRange.length > 0 else {
            if let debugContext {
                debugLog("\(debugContext) AXSelectedTextRange empty or unreadable")
            }
            return nil
        }

        return (
            NSRange(location: cfRange.location, length: cfRange.length),
            axValue
        )
    }

    private func selectedTextMarkerRange(from element: AXUIElement, debugContext: String? = nil) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextMarkerRangeAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            if let debugContext {
                debugLog("\(debugContext) AXSelectedTextMarkerRange error=\(String(describing: result))")
            }
            return nil
        }
        return value
    }

    private func bounds(for rangeValue: AXValue, in element: AXUIElement, debugContext: String? = nil) -> CGRect? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        guard result == .success, let value else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForRange error=\(String(describing: result))")
            }
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForRange unexpected type")
            }
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForRange not cgRect")
            }
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForRange unreadable")
            }
            return nil
        }

        return rect
    }

    private func string(
        for rangeValue: AXValue,
        in element: AXUIElement,
        debugContext: String? = nil
    ) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        guard result == .success else {
            if let debugContext {
                debugLog("\(debugContext) AXStringForRange error=\(String(describing: result))")
            }
            return nil
        }
        return value as? String
    }

    private func string(
        forTextMarkerRange markerRange: CFTypeRef,
        in element: AXUIElement,
        debugContext: String? = nil
    ) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForTextMarkerRangeParameterizedAttribute as CFString,
            markerRange,
            &value
        )
        guard result == .success else {
            if let debugContext {
                debugLog("\(debugContext) AXStringForTextMarkerRange error=\(String(describing: result))")
            }
            return nil
        }
        return value as? String
    }

    private func attributedString(
        forTextMarkerRange markerRange: CFTypeRef,
        in element: AXUIElement,
        debugContext: String? = nil
    ) -> NSAttributedString? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXAttributedStringForTextMarkerRangeParameterizedAttribute as CFString,
            markerRange,
            &value
        )
        guard result == .success else {
            if let debugContext {
                debugLog("\(debugContext) AXAttributedStringForTextMarkerRange error=\(String(describing: result))")
            }
            return nil
        }
        return value as? NSAttributedString
    }

    private func bounds(
        forTextMarkerRange markerRange: CFTypeRef,
        in element: AXUIElement,
        debugContext: String? = nil
    ) -> CGRect? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForTextMarkerRangeParameterizedAttribute as CFString,
            markerRange,
            &value
        )
        guard result == .success, let value else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForTextMarkerRange error=\(String(describing: result))")
            }
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForTextMarkerRange unexpected type")
            }
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForTextMarkerRange not cgRect")
            }
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForTextMarkerRange unreadable")
            }
            return nil
        }

        return rect
    }

    private func accessibilityPoint(for point: CGPoint) -> CGPoint {
        guard let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() else {
            return point
        }

        return CGPoint(
            x: point.x,
            y: globalMaxY - point.y
        )
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

    private func configureMessagingTimeout(for element: AXUIElement, timeout: Float = 1.5) {
        let result = AXUIElementSetMessagingTimeout(element, timeout)
        if result != .success {
            debugLog("set timeout failed error=\(String(describing: result)) timeout=\(timeout)")
        }
    }

    private func appendUnique(_ newCandidates: [CandidateElement], to candidates: inout [CandidateElement]) {
        for candidate in newCandidates where !candidates.contains(where: { CFEqual($0.element, candidate.element) }) {
            candidates.append(candidate)
        }
    }

    private func debugSummary(of element: AXUIElement) -> String {
        let role = stringAttribute(kAXRoleAttribute as CFString, from: element) ?? "nil"
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: element) ?? "nil"
        let identifier = stringAttribute(kAXIdentifierAttribute as CFString, from: element) ?? "nil"
        let title = stringAttribute(kAXTitleAttribute as CFString, from: element) ?? "nil"
        let value = stringAttribute(kAXValueAttribute as CFString, from: element).map { truncate($0) } ?? "nil"
        return "role=\(role) subrole=\(subrole) identifier=\(identifier) title=\(truncate(title)) value=\(value)"
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }
        return value as? String
    }

    private func describe(point: CGPoint) -> String {
        "(\(format(point.x)), \(format(point.y)))"
    }

    private func describe(rect: CGRect) -> String {
        "x=\(format(rect.origin.x)) y=\(format(rect.origin.y)) w=\(format(rect.width)) h=\(format(rect.height))"
    }

    private func describe(range: NSRange?) -> String {
        guard let range else { return "nil" }
        return "{\(range.location), \(range.length)}"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    private func truncate(_ text: String, limit: Int = 120) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "..."
    }

    private func debugLog(_ message: String) {
#if DEBUG
        print("[SelectedText] \(message)")
#endif
    }
}
