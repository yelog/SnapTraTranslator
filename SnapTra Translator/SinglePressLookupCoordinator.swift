import CoreGraphics
import Foundation

nonisolated struct SinglePressLookupRequest: Equatable, Sendable {
    let lookupID: UUID
    let mouseLocation: CGPoint
    let supportsSelectedText: Bool
    let selectedTextEnabled: Bool
    let clipboardFallbackEnabled: Bool
    let hasAccessibilityPermission: Bool
    let selectedTextProbeRequest: SelectedTextProbeRequest?

    init(
        lookupID: UUID,
        mouseLocation: CGPoint,
        supportsSelectedText: Bool,
        selectedTextEnabled: Bool,
        clipboardFallbackEnabled: Bool,
        hasAccessibilityPermission: Bool,
        selectedTextProbeRequest: SelectedTextProbeRequest? = nil
    ) {
        self.lookupID = lookupID
        self.mouseLocation = mouseLocation
        self.supportsSelectedText = supportsSelectedText
        self.selectedTextEnabled = selectedTextEnabled
        self.clipboardFallbackEnabled = clipboardFallbackEnabled
        self.hasAccessibilityPermission = hasAccessibilityPermission
        self.selectedTextProbeRequest = selectedTextProbeRequest
    }

    var executionPolicy: SinglePressLookupExecutionPolicy {
        guard supportsSelectedText,
              selectedTextEnabled,
              hasAccessibilityPermission else {
            return .ocrOnly
        }

        return .selectionFirst(allowsClipboardFallback: clipboardFallbackEnabled)
    }
}

nonisolated enum SinglePressLookupExecutionPolicy: Equatable, Sendable {
    case ocrOnly
    case selectionFirst(allowsClipboardFallback: Bool)
}

nonisolated struct SinglePressLookupResolution: Sendable {
    let intent: SinglePressLookupIntent
    let shouldTryClipboardFallback: Bool
}

nonisolated enum SinglePressLookupDecision<Candidate: Sendable>: Sendable {
    case selectedText(SelectedTextSnapshot)
    case ocr(Candidate)
    case cancelled
}

nonisolated enum SinglePressLookupResolvedRoute: Equatable, Sendable {
    case selectedText(SelectedTextSnapshotSource)
    case ocr
}

nonisolated enum SinglePressLookupCoordinator {
    @MainActor
    static func resolve<Candidate: Sendable>(
        request: SinglePressLookupRequest,
        accessibilityProbe: @escaping @MainActor @Sendable (
            SinglePressLookupRequest
        ) async -> SinglePressLookupResolution,
        clipboardProbe: @escaping @MainActor @Sendable (
            SinglePressLookupRequest
        ) async -> SelectedTextSnapshot?,
        loadOCRCandidate: @escaping @MainActor @Sendable (
            SinglePressLookupRequest
        ) async -> Candidate,
        routeResolved: @escaping @MainActor @Sendable (
            SinglePressLookupResolvedRoute
        ) -> Void
    ) async -> SinglePressLookupDecision<Candidate> {
        guard !Task.isCancelled else { return .cancelled }

        switch request.executionPolicy {
        case .ocrOnly:
            routeResolved(.ocr)
            let candidate = await loadOCRCandidate(request)
            guard !Task.isCancelled else { return .cancelled }
            return .ocr(candidate)

        case .selectionFirst(let allowsClipboardFallback):
            let accessibilityResolution = await accessibilityProbe(request)
            guard !Task.isCancelled else { return .cancelled }

            if case .selectedTextSentence(let snapshot) = accessibilityResolution.intent {
                routeResolved(.selectedText(snapshot.source))
                return .selectedText(snapshot)
            }

            guard allowsClipboardFallback,
                  accessibilityResolution.shouldTryClipboardFallback else {
                routeResolved(.ocr)
                let candidate = await loadOCRCandidate(request)
                guard !Task.isCancelled else { return .cancelled }
                return .ocr(candidate)
            }

            // Start both operations only after AX reports an uncertain route. The
            // clipboard freshness decision remains authoritative even when OCR
            // finishes first, while cancellation prevents speculative work from
            // committing any UI, audio, or persistence side effect.
            let clipboardTask = Task { @MainActor in
                await clipboardProbe(request)
            }
            let ocrTask = Task { @MainActor in
                await loadOCRCandidate(request)
            }

            return await withTaskCancellationHandler {
                let clipboardSnapshot = await clipboardTask.value
                guard !Task.isCancelled else {
                    ocrTask.cancel()
                    return .cancelled
                }

                if let clipboardSnapshot,
                   case .selectedTextSentence = SinglePressLookupRouter.resolve(
                       mouseLocation: request.mouseLocation,
                       isSelectedTextTranslationSupported: request.supportsSelectedText,
                       isSelectedTextTranslationEnabled: request.selectedTextEnabled,
                       hasAccessibilityPermission: request.hasAccessibilityPermission,
                       selectionSnapshot: clipboardSnapshot
                   ) {
                    ocrTask.cancel()
                    routeResolved(.selectedText(clipboardSnapshot.source))
                    return .selectedText(clipboardSnapshot)
                }

                routeResolved(.ocr)
                let candidate = await ocrTask.value
                guard !Task.isCancelled else { return .cancelled }
                return .ocr(candidate)
            } onCancel: {
                clipboardTask.cancel()
                ocrTask.cancel()
            }
        }
    }
}
