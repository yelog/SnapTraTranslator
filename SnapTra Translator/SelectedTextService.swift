import AppKit
import ApplicationServices
import Dispatch
import Foundation

nonisolated enum SelectedTextSnapshotSource: Equatable, Sendable {
    case accessibility
    case clipboard
}

nonisolated struct SelectedTextSnapshot: Equatable, Sendable {
    let text: String
    let rawText: String
    let selectedRange: NSRange
    let bounds: CGRect?
    let sourceAppIdentifier: String?
    let sourceProcessIdentifier: pid_t?
    let source: SelectedTextSnapshotSource
    let replacementContextID: UUID?

    init(
        text: String,
        selectedRange: NSRange,
        bounds: CGRect?,
        sourceAppIdentifier: String?,
        source: SelectedTextSnapshotSource = .accessibility,
        rawText: String? = nil,
        sourceProcessIdentifier: pid_t? = nil,
        replacementContextID: UUID? = nil
    ) {
        self.text = text
        self.rawText = rawText ?? text
        self.selectedRange = selectedRange
        self.bounds = bounds
        self.sourceAppIdentifier = sourceAppIdentifier
        self.sourceProcessIdentifier = sourceProcessIdentifier
        self.source = source
        self.replacementContextID = replacementContextID
    }
}

nonisolated enum ClipboardFallbackPolicy {
    static func shouldReadCopiedText(
        originalChangeCount: Int,
        currentChangeCount: Int
    ) -> Bool {
        currentChangeCount != originalChangeCount
    }

    static func shouldTryAfterAccessibilityRejection(_ reason: String?) -> Bool {
        switch reason {
        case "missingBounds", "untrustedBounds", "mouseOutsideSelection":
            return true
        default:
            return false
        }
    }
}

@MainActor
enum ClipboardSelectionOperationGate {
    private static var isActive = false

    static func acquire() -> Bool {
        guard !isActive else { return false }
        isActive = true
        return true
    }

    static func release() {
        isActive = false
    }
}

nonisolated final class SelectedTextService: @unchecked Sendable {
    private let probeExecutor: SelectedTextProbeExecutor
    private let diagnostics: SelectedTextDiagnostics
    private let probeObserver: @Sendable (SelectedTextProbeObservation) -> Void
    private let replacementEnabled: Bool
    private var replacementContexts: [UUID: ReplacementContext] = [:]

    private struct ReplacementContext {
        let application: AXUIElement
        let window: AXUIElement
        let element: AXUIElement
        let processIdentifier: pid_t
        let range: NSRange
        let rawText: String
    }

    init(
        probeExecutor: SelectedTextProbeExecutor = .shared,
        diagnostics: SelectedTextDiagnostics = .system,
        replacementEnabled: Bool = false,
        probeObserver: @escaping @Sendable (SelectedTextProbeObservation) -> Void = { _ in }
    ) {
        self.probeExecutor = probeExecutor
        self.diagnostics = diagnostics
        self.replacementEnabled = replacementEnabled
        self.probeObserver = probeObserver
    }

    @MainActor
    func currentSelectionSnapshot(mouseLocation: CGPoint) async -> SelectedTextSnapshot? {
        guard let request = SelectedTextProbeRequest.capture(mouseLocation: mouseLocation) else { return nil }
        return await currentSelectionSnapshot(request: request)
    }

    func currentSelectionSnapshot(request: SelectedTextProbeRequest) async -> SelectedTextSnapshot? {
        guard await request.hasCurrentScreenConfiguration else { return nil }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let snapshot: SelectedTextSnapshot?

        do {
            snapshot = try await probeExecutor.execute(onDiscardedResult: { [self] snapshot in
                if let contextID = snapshot?.replacementContextID {
                    replacementContexts.removeValue(forKey: contextID)
                }
            }) { [self] cancellation in
                axSelectionSnapshot(
                    request: request,
                    cancellation: cancellation
                )
            }
        } catch {
            snapshot = nil
        }

        guard !Task.isCancelled, await request.hasCurrentScreenConfiguration else {
            if let contextID = snapshot?.replacementContextID {
                // Cleanup must finish even when the caller was cancelled by a display change.
                await Task { [self] in await releaseReplacementContext(contextID) }.value
            }
            return nil
        }

        let endedAt = DispatchTime.now().uptimeNanoseconds
        return SelectedTextProbeSoftBudget.observe(
            snapshot,
            durationNanoseconds: endedAt >= startedAt ? endedAt - startedAt : 0,
            observer: probeObserver
        )
    }

    @MainActor
    func hoveredStaticText(request: SelectedTextProbeRequest) async -> (text: String, bounds: CGRect)? {
        guard let processIdentifier = request.frontmostApplicationProcessIdentifier,
              processIdentifier != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier,
              request.hasCurrentScreenConfiguration else { return nil }

        let hoveredText = try? await probeExecutor.execute { [self] cancellation -> (text: String, bounds: CGRect)? in
            let application = AXUIElementCreateApplication(processIdentifier)
            configureMessagingTimeout(for: application, timeout: 0.1)
            guard let hoveredElement = element(
                at: request.accessibilityPoint,
                from: application,
                source: "frontmostApp"
            ) else {
                return nil
            }

            try cancellation.checkCancellation()
            var elementProcessIdentifier: pid_t = 0
            guard AXUIElementGetPid(hoveredElement, &elementProcessIdentifier) == .success,
                  elementProcessIdentifier == processIdentifier else { return nil }
            configureMessagingTimeout(for: hoveredElement, timeout: 0.1)

            let attributes = [kAXRoleAttribute, kAXValueAttribute, kAXPositionAttribute, kAXSizeAttribute] as CFArray
            var rawValues: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(hoveredElement, attributes, [], &rawValues) == .success,
                  let values = rawValues as? [AnyObject], values.count == 4,
                  values[0] as? String == kAXStaticTextRole,
                  let text = (values[1] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  text.unicodeScalars.contains(where: CharacterSet.letters.contains),
                  CFGetTypeID(values[2]) == AXValueGetTypeID(),
                  CFGetTypeID(values[3]) == AXValueGetTypeID() else { return nil }

            var position = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(unsafeBitCast(values[2], to: AXValue.self), .cgPoint, &position),
                  AXValueGetValue(unsafeBitCast(values[3], to: AXValue.self), .cgSize, &size),
                  [position.x, position.y, size.width, size.height].allSatisfy(\.isFinite),
                  size.width > 0, size.height > 0 else { return nil }

            let bounds = request.normalizedScreenRect(CGRect(origin: position, size: size))
            guard bounds.contains(request.mouseLocation) else { return nil }
            return (text, bounds)
        }

        guard !Task.isCancelled, request.hasCurrentScreenConfiguration,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier else { return nil }
        return hoveredText
    }

    /// Clipboard-based fallback that uses Cmd+C simulation.
    /// Must be called from an async context to avoid blocking the main thread.
    @MainActor
    func clipboardFallbackSnapshot(isEnabled: Bool) async -> SelectedTextSnapshot? {
        guard isEnabled else { return nil }
        debugLog("trying clipboard fallback")
        return await clipboardSelectionSnapshot()
    }

    private func axSelectionSnapshot(
        request: SelectedTextProbeRequest,
        cancellation: SelectedTextProbeCancellation
    ) -> SelectedTextSnapshot? {
        guard !cancellation.isCancelled else { return nil }
        let systemWideElement = AXUIElementCreateSystemWide()
        configureMessagingTimeout(for: systemWideElement)

        guard !cancellation.isCancelled else { return nil }
        let frontmostAppElement = request.frontmostApplicationProcessIdentifier.map {
            AXUIElementCreateApplication($0)
        }
        if let frontmostAppElement {
            configureMessagingTimeout(for: frontmostAppElement)
        }

        let candidates = candidateSequence(
            systemWideElement: systemWideElement,
            frontmostAppElement: frontmostAppElement,
            request: request,
            cancellation: cancellation
        )

        debugLog(
            "start mouse=\(describe(point: request.mouseLocation)) frontmostApp=\(request.sourceAppIdentifier ?? "nil")"
        )

        let snapshot = SelectedTextProbePolicy.snapshot(
            candidates: candidates,
            sourceAppIdentifier: request.sourceAppIdentifier,
            sourceProcessIdentifier: request.frontmostApplicationProcessIdentifier,
            normalizeBounds: request.normalizedScreenRect,
            diagnostics: diagnostics,
            isCancelled: { cancellation.isCancelled },
            allowsReplacementContext: replacementEnabled
        )
        debugLog(
            snapshot.map {
                "success text=\"\(truncate($0.text))\" bounds=\($0.bounds.map { describe(rect: $0) } ?? "nil")"
            } ?? "no selection snapshot from AXUIElement"
        )
        return snapshot
    }

    private func candidateSequence(
        systemWideElement: AXUIElement,
        frontmostAppElement: AXUIElement?,
        request: SelectedTextProbeRequest,
        cancellation: SelectedTextProbeCancellation,
        maxDepth: Int = 8
    ) -> AnySequence<SelectedTextProbeCandidate> {
        let rootProviders: [(source: String, element: () -> AXUIElement?)] = [
            (
                "frontmostApp-hovered",
                { [self] in
                    guard let frontmostAppElement else { return nil }
                    return element(
                        at: request.accessibilityPoint,
                        from: frontmostAppElement,
                        source: "frontmostApp"
                    )
                }
            ),
            (
                "systemWide-hovered",
                { [self] in
                    element(
                        at: request.accessibilityPoint,
                        from: systemWideElement,
                        source: "systemWide"
                    )
                }
            ),
            (
                "frontmostApp-focusedElement",
                { [self] in
                    guard let frontmostAppElement else { return nil }
                    return focusedElement(from: frontmostAppElement, source: "frontmostApp")
                }
            ),
            (
                "frontmostApp-focusedWindow",
                { [self] in
                    guard let frontmostAppElement else { return nil }
                    return focusedWindow(from: frontmostAppElement)
                }
            ),
            (
                "systemWide-focusedApplication",
                { [self] in focusedApplication(from: systemWideElement) }
            ),
            (
                "systemWide-focusedElement",
                { [self] in focusedElement(from: systemWideElement, source: "systemWide") }
            ),
        ]

        return AnySequence { [self] in
            var rootIndex = 0
            var activeElement: AXUIElement?
            var activeSource = ""
            var activeDepth = 0
            var shouldAdvanceToParent = false
            var seenElements: [AXUIElement] = []
            var candidateIndex = 0

            return AnyIterator<SelectedTextProbeCandidate> { [self] in
                while !cancellation.isCancelled {
                    if shouldAdvanceToParent, let currentElement = activeElement {
                        guard activeDepth + 1 < maxDepth else {
                            activeElement = nil
                            shouldAdvanceToParent = false
                            continue
                        }

                        guard !cancellation.isCancelled else { return nil }
                        guard let parentElement = parent(of: currentElement) else {
                            activeElement = nil
                            shouldAdvanceToParent = false
                            continue
                        }
                        guard !cancellation.isCancelled else { return nil }

                        activeElement = parentElement
                        activeDepth += 1
                    } else {
                        guard rootIndex < rootProviders.count else { return nil }
                        let provider = rootProviders[rootIndex]
                        rootIndex += 1

                        guard !cancellation.isCancelled else { return nil }
                        guard let rootElement = provider.element() else { continue }
                        guard !cancellation.isCancelled else { return nil }

                        activeElement = rootElement
                        activeSource = provider.source
                        activeDepth = 0
                        shouldAdvanceToParent = true
                    }

                    guard let candidateElement = activeElement else { continue }
                    guard !seenElements.contains(where: { CFEqual($0, candidateElement) }) else {
                        continue
                    }
                    seenElements.append(candidateElement)

                    let context = "candidate[\(candidateIndex)] \(activeSource)#\(activeDepth)"
                    candidateIndex += 1
                    return probeCandidate(
                        element: candidateElement,
                        request: request,
                        context: context
                    )
                }

                return nil
            }
        }
    }

    private func probeCandidate(
        element: AXUIElement,
        request: SelectedTextProbeRequest,
        context: String
    ) -> SelectedTextProbeCandidate {
        SelectedTextProbeCandidate(
            context: context,
            debugSummary: { [self] in debugSummary(of: element) },
            commitSelectionContext: { [self] range, rawText, _ in
                replacementContextID(
                    for: element,
                    range: range,
                    rawText: rawText,
                    request: request
                )
            },
            selectedText: { [self] in
                selectedText(from: element, debugContext: context)
            },
            selectedRange: { [self] in
                guard let result = selectedRange(
                    from: element,
                    debugContext: context
                ) else {
                    return nil
                }

                return SelectedTextProbeRange(
                    range: result.range,
                    string: { [self] in
                        string(
                            for: result.axValue,
                            in: element,
                            debugContext: context
                        )
                    },
                    bounds: { [self] in
                        bounds(
                            for: result.axValue,
                            in: element,
                            debugContext: context
                        )
                    }
                )
            },
            selectedTextMarkerRange: { [self] in
                guard let markerRange = selectedTextMarkerRange(
                    from: element,
                    debugContext: context
                ) else {
                    return nil
                }

                return SelectedTextProbeMarkerRange(
                    string: { [self] in
                        string(
                            forTextMarkerRange: markerRange,
                            in: element,
                            debugContext: context
                        )
                    },
                    attributedString: { [self] in
                        attributedString(
                            forTextMarkerRange: markerRange,
                            in: element,
                            debugContext: context
                        )
                    },
                    bounds: { [self] in
                        bounds(
                            forTextMarkerRange: markerRange,
                            in: element,
                            debugContext: context
                        )
                    }
                )
            }
        )
    }

    private func replacementContextID(
        for element: AXUIElement,
        range: NSRange,
        rawText: String,
        request: SelectedTextProbeRequest
    ) -> UUID? {
        guard replacementEnabled else { return nil }
        guard let processIdentifier = request.frontmostApplicationProcessIdentifier else {
            debugLog("replacement capture rejected reason=missingSourceProcess")
            return nil
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        configureMessagingTimeout(for: application, timeout: 0.1)
        var elementProcessIdentifier: pid_t = 0
        guard AXUIElementGetPid(element, &elementProcessIdentifier) == .success,
              elementProcessIdentifier == processIdentifier else {
            debugLog("replacement capture rejected reason=sourceProcessMismatch")
            return nil
        }
        guard let window = window(of: element),
              let focusedWindow = focusedWindow(from: application),
              CFEqual(window, focusedWindow) else {
            debugLog("replacement capture rejected reason=windowMismatch")
            return nil
        }
        guard let focusedElement = focusedElement(from: application, source: nil) else {
            debugLog("replacement capture rejected reason=focusMismatch")
            return nil
        }

        let isSameElement = CFEqual(element, focusedElement)
        let relationship: SelectedTextReplacementPolicy.CandidateRelationship
        if isSameElement {
            relationship = .sameElement
        } else if isAncestor(focusedElement, of: element) {
            relationship = .insideFocusedElement
        } else if isAncestor(element, of: focusedElement) {
            relationship = .containsFocusedElement
        } else {
            relationship = .unrelated
        }
        var focusedProcessIdentifier: pid_t = 0
        guard AXUIElementGetPid(focusedElement, &focusedProcessIdentifier) == .success,
              focusedProcessIdentifier == processIdentifier,
              let focusedElementWindow = self.window(of: focusedElement),
              CFEqual(window, focusedElementWindow),
              SelectedTextReplacementPolicy.canBindCandidate(
                relationship: relationship
              ) else {
            debugLog("replacement capture rejected reason=focusMismatch")
            return nil
        }

        let targetElement = focusedElement
        guard let selection = selectedRange(from: targetElement) else {
            debugLog("replacement capture rejected reason=missingFocusedSelectionRange")
            return nil
        }
        let expectedRange = isSameElement && range.location != NSNotFound ? range : selection.range
        let rangeText = string(for: selection.axValue, in: targetElement)
        guard SelectedTextReplacementPolicy.selectionTextMatches(
            rawText: rawText,
            rangeText: rangeText,
            selectedText: selectedText(from: targetElement),
            currentRange: selection.range,
            expectedRange: expectedRange
        ) else {
            debugLog("replacement capture rejected reason=selectionMismatch rangeTextAvailable=\(rangeText != nil)")
            return nil
        }

        let isSecure = isSecureTextElement(targetElement)
        guard SelectedTextReplacementPolicy.canCaptureSelection(
            supportsChannel: replacementEnabled,
            isFrontmostApplication: true,
            isFocusedElement: true,
            isSameWindow: true,
            isSecure: isSecure,
            range: selection.range,
            rawText: rawText
        ) else {
            debugLog("replacement capture rejected reason=invalidSelection secure=\(isSecure)")
            return nil
        }

        let contextID = UUID()
        replacementContexts[contextID] = ReplacementContext(
            application: application,
            window: window,
            element: targetElement,
            processIdentifier: processIdentifier,
            range: selection.range,
            rawText: rawText
        )
        if replacementContexts.count > 8,
           let oldestID = replacementContexts.keys.first(where: { $0 != contextID }) {
            replacementContexts.removeValue(forKey: oldestID)
        }
        debugLog("replacement selection captured rangeTextAvailable=\(rangeText != nil)")
        return contextID
    }

    func releaseReplacementContext(_ contextID: UUID?) async {
        guard let contextID else { return }
        _ = try? await probeExecutor.execute { [self] _ in
            replacementContexts.removeValue(forKey: contextID)
            return true
        }
    }

    func releaseAllReplacementContexts() async {
        _ = try? await probeExecutor.execute { [self] _ in
            replacementContexts.removeAll(keepingCapacity: false)
            return true
        }
    }

    func validateReplacementTarget(
        contextID: UUID,
        frontmostProcessIdentifier: pid_t?
    ) async throws {
        try await probeExecutor.execute { [self] _ in
            guard let context = replacementContexts[contextID] else {
                throw SelectedTextReplacementFailure.targetUnavailable
            }
            guard frontmostProcessIdentifier == context.processIdentifier else {
                throw SelectedTextReplacementFailure.sourceChanged
            }
            guard let focusedWindow = focusedWindow(from: context.application),
                  let focusedElement = focusedElement(from: context.application, source: nil) else {
                throw SelectedTextReplacementFailure.targetUnavailable
            }
            let selection = selectedRange(from: context.element)
            let rangeText = selection.flatMap { string(for: $0.axValue, in: context.element) }
            guard SelectedTextReplacementPolicy.targetStillMatches(
                expectedProcessIdentifier: context.processIdentifier,
                currentProcessIdentifier: frontmostProcessIdentifier,
                isSameWindow: CFEqual(focusedWindow, context.window),
                isSameFocusedElement: CFEqual(focusedElement, context.element),
                currentRange: selection?.range,
                expectedRange: context.range,
                currentRawText: rangeText ?? selectedText(from: context.element),
                expectedRawText: context.rawText
            ), SelectedTextReplacementPolicy.selectionTextMatches(
                rawText: context.rawText,
                rangeText: rangeText,
                selectedText: selectedText(from: context.element),
                currentRange: selection?.range,
                expectedRange: context.range
            ) else {
                throw SelectedTextReplacementFailure.selectionChanged
            }
            guard SelectedTextReplacementPolicy.isEditableTarget(
                enabled: enabledState(of: context.element),
                isSecure: isSecureTextElement(context.element),
                selectedTextIsSettable: isAttributeSettable(kAXSelectedTextAttribute as CFString, on: context.element),
                valueIsSettable: isAttributeSettable(kAXValueAttribute as CFString, on: context.element)
            ) else {
                throw SelectedTextReplacementFailure.targetNotEditable
            }
        }
    }

    func replacementTargetMatches(
        contextID: UUID,
        frontmostProcessIdentifier: pid_t?
    ) async -> Bool {
        do {
            try await validateReplacementTarget(contextID: contextID, frontmostProcessIdentifier: frontmostProcessIdentifier)
            return true
        } catch {
            return false
        }
    }

    func replacementTextMatches(contextID: UUID, text: String) async -> Bool {
        (try? await probeExecutor.execute { [self] _ in
            guard let context = replacementContexts[contextID],
                  let window = focusedWindow(from: context.application),
                  CFEqual(window, context.window),
                  let element = focusedElement(from: context.application, source: nil),
                  CFEqual(element, context.element),
                  text.utf16.count <= Int.max - context.range.location else {
                return false
            }

            var cfRange = CFRange(
                location: context.range.location,
                length: text.utf16.count
            )
            guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
            return string(for: value, in: context.element) == text
        }) ?? false
    }

    private func window(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXWindowAttribute as CFString,
            &value
        )
        guard result == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func isAncestor(_ ancestor: AXUIElement, of element: AXUIElement) -> Bool {
        var current = parent(of: element)
        for _ in 0..<8 {
            guard let candidate = current else { return false }
            if CFEqual(candidate, ancestor) { return true }
            current = parent(of: candidate)
        }
        return false
    }

    private func enabledState(of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXEnabledAttribute as CFString,
            &value
        )
        if result == .attributeUnsupported || result == .noValue { return nil }
        guard result == .success, let enabled = value as? Bool else { return false }
        return enabled
    }

    private func isSecureTextElement(_ element: AXUIElement) -> Bool {
        stringAttribute(kAXSubroleAttribute as CFString, from: element) == kAXSecureTextFieldSubrole as String
    }

    private func isAttributeSettable(_ attribute: CFString, on element: AXUIElement) -> Bool {
        var isSettable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &isSettable) == .success
            && isSettable.boolValue
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

    private func element(
        at accessibilityPoint: CGPoint,
        from rootElement: AXUIElement,
        source: String
    ) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            rootElement,
            Float(accessibilityPoint.x),
            Float(accessibilityPoint.y),
            &element
        )
        guard result == .success else {
            debugLog(
                "\(source) hovered element lookup failed axPoint=\(describe(point: accessibilityPoint)) error=\(String(describing: result))"
            )
            return nil
        }
        return element
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

    private func configureMessagingTimeout(for element: AXUIElement, timeout: Float = 1.5) {
        let result = AXUIElementSetMessagingTimeout(element, timeout)
        if result != .success {
            debugLog("set timeout failed error=\(String(describing: result)) timeout=\(timeout)")
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

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    private func truncate(_ text: String, limit: Int = 120) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "..."
    }

    // MARK: - Clipboard Fallback

    @MainActor
    private func clipboardSelectionSnapshot() async -> SelectedTextSnapshot? {
        guard ClipboardSelectionOperationGate.acquire() else {
            debugLog("clipboard fallback: another clipboard operation is active")
            return nil
        }
        defer { ClipboardSelectionOperationGate.release() }

        let pasteboard = NSPasteboard.general

        // Save current clipboard state
        let originalChangeCount = pasteboard.changeCount
        let originalItems = savePasteboardItems(from: pasteboard)
        var ownedChangeCount = originalChangeCount
        var shouldRestorePasteboard = false
        defer {
            if shouldRestorePasteboard,
               SelectedTextReplacementPolicy.shouldRestorePasteboard(
                currentChangeCount: pasteboard.changeCount,
                ownedChangeCount: ownedChangeCount
            ) {
                restorePasteboard(items: originalItems, to: pasteboard)
            }
        }

        // Simulate Cmd+C
        simulateCmdC()

        // Wait for clipboard to update (up to 150ms) using async sleep to avoid blocking main thread
        for _ in 0..<15 {
            guard !Task.isCancelled else {
                debugLog("clipboard fallback: cancelled")
                return nil
            }
            if pasteboard.changeCount != originalChangeCount {
                ownedChangeCount = pasteboard.changeCount
                shouldRestorePasteboard = true
                break
            }
            do {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            } catch {
                debugLog("clipboard fallback: cancelled while waiting")
                return nil
            }
        }

        guard !Task.isCancelled else { return nil }
        guard ClipboardFallbackPolicy.shouldReadCopiedText(
            originalChangeCount: originalChangeCount,
            currentChangeCount: pasteboard.changeCount
        ) else {
            debugLog("clipboard fallback: pasteboard unchanged")
            return nil
        }

        // Read selected text from clipboard
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            debugLog("clipboard fallback: no text on pasteboard")
            return nil
        }

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let snapshot = SelectedTextSnapshot(
            text: normalizedText,
            selectedRange: NSRange(location: NSNotFound, length: normalizedText.utf16.count),
            bounds: nil,
            sourceAppIdentifier: frontmostApp?.bundleIdentifier,
            source: .clipboard,
            rawText: text,
            sourceProcessIdentifier: frontmostApp?.processIdentifier
        )

        return snapshot
    }

    private func simulateCmdC() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            debugLog("clipboard fallback: failed to create event source")
            return
        }

        let keyCodeC: CGKeyCode = 0x08

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeC, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeC, keyDown: false) else {
            debugLog("clipboard fallback: failed to create key events")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private struct PasteboardBackup {
        let changeCount: Int
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private func savePasteboardItems(from pasteboard: NSPasteboard) -> PasteboardBackup {
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        if let pasteboardItems = pasteboard.pasteboardItems {
            for item in pasteboardItems {
                var dict: [NSPasteboard.PasteboardType: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) {
                        dict[type] = data
                    }
                }
                items.append(dict)
            }
        }
        return PasteboardBackup(changeCount: pasteboard.changeCount, items: items)
    }

    private func restorePasteboard(items backup: PasteboardBackup, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = backup.items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        diagnostics.log(message())
    }
}
