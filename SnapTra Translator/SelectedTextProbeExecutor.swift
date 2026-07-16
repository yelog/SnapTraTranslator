import AppKit
import Dispatch
import Foundation

nonisolated struct SelectedTextProbeRequest: Equatable, Sendable {
    let mouseLocation: CGPoint
    let frontmostApplicationProcessIdentifier: pid_t?
    let sourceAppIdentifier: String?
    let globalScreenMaxY: CGFloat?

    @MainActor
    static func capture(mouseLocation: CGPoint) -> SelectedTextProbeRequest {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        return SelectedTextProbeRequest(
            mouseLocation: mouseLocation,
            frontmostApplicationProcessIdentifier: frontmostApplication?.processIdentifier,
            sourceAppIdentifier: frontmostApplication?.bundleIdentifier,
            globalScreenMaxY: NSScreen.screens.map(\.frame.maxY).max()
        )
    }

    var accessibilityPoint: CGPoint {
        guard let globalScreenMaxY else { return mouseLocation }
        return CGPoint(
            x: mouseLocation.x,
            y: globalScreenMaxY - mouseLocation.y
        )
    }

    func normalizedScreenRect(_ rect: CGRect) -> CGRect {
        guard let globalScreenMaxY else { return rect }
        return CGRect(
            x: rect.minX,
            y: globalScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

nonisolated final class SelectedTextProbeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    fileprivate func cancel() {
        lock.withLock {
            cancelled = true
        }
    }

    func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }
}

nonisolated final class SelectedTextProbeExecutor: @unchecked Sendable {
    static let shared = SelectedTextProbeExecutor()

    private let queue: DispatchQueue

    init(label: String = "app.snaptra.selected-text-probe") {
        queue = DispatchQueue(
            label: label,
            qos: .userInitiated
        )
    }

    func execute<Result: Sendable>(
        _ operation: @escaping @Sendable (SelectedTextProbeCancellation) throws -> Result
    ) async throws -> Result {
        let cancellation = SelectedTextProbeCancellation()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        try cancellation.checkCancellation()
                        let result = try operation(cancellation)
                        try cancellation.checkCancellation()
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}

nonisolated struct SelectedTextDiagnostics: @unchecked Sendable {
    private let isEnabled: Bool
    private let sink: (String) -> Void

    init(
        isEnabled: Bool,
        sink: @escaping (String) -> Void = { print("[SelectedText] \($0)") }
    ) {
        self.isEnabled = isEnabled
        self.sink = sink
    }

    func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        sink(message())
    }

    static var system: SelectedTextDiagnostics {
#if DEBUG
        SelectedTextDiagnostics(isEnabled: true)
#else
        SelectedTextDiagnostics(isEnabled: false)
#endif
    }
}

nonisolated struct SelectedTextProbeObservation: Equatable, Sendable {
    static let softBudgetNanoseconds: UInt64 = 120_000_000

    let durationNanoseconds: UInt64

    var exceededSoftBudget: Bool {
        durationNanoseconds > Self.softBudgetNanoseconds
    }
}

nonisolated enum SelectedTextProbeSoftBudget {
    static func observe<Result>(
        _ result: Result,
        durationNanoseconds: UInt64,
        observer: (SelectedTextProbeObservation) -> Void
    ) -> Result {
        observer(
            SelectedTextProbeObservation(
                durationNanoseconds: durationNanoseconds
            )
        )
        return result
    }
}

nonisolated struct SelectedTextProbeRange {
    let range: NSRange
    let string: () -> String?
    let bounds: () -> CGRect?
}

nonisolated struct SelectedTextProbeMarkerRange {
    let string: () -> String?
    let attributedString: () -> NSAttributedString?
    let bounds: () -> CGRect?
}

nonisolated struct SelectedTextProbeCandidate {
    let context: String
    let debugSummary: () -> String
    let selectedText: () -> String?
    let selectedRange: () -> SelectedTextProbeRange?
    let selectedTextMarkerRange: () -> SelectedTextProbeMarkerRange?
}

nonisolated enum SelectedTextProbePolicy {
    static func snapshot(
        candidates: AnySequence<SelectedTextProbeCandidate>,
        sourceAppIdentifier: String?,
        normalizeBounds: (CGRect) -> CGRect,
        diagnostics: SelectedTextDiagnostics = .system,
        isCancelled: () -> Bool = { false }
    ) -> SelectedTextSnapshot? {
        for candidate in candidates {
            guard !isCancelled() else { return nil }

            diagnostics.log("\(candidate.context) \(candidate.debugSummary())")

            guard !isCancelled() else { return nil }
            let directText = normalized(candidate.selectedText())

            guard !isCancelled() else { return nil }
            let range = candidate.selectedRange()
            let selectedRange = range?.range
                ?? NSRange(
                    location: NSNotFound,
                    length: directText?.utf16.count ?? 0
                )
            let hasKnownRange = isKnown(selectedRange)

            if let directText, hasKnownRange {
                return makeSnapshot(
                    text: directText,
                    selectedRange: selectedRange,
                    bounds: nil,
                    sourceAppIdentifier: sourceAppIdentifier
                )
            }

            var resolvedText = directText
            if resolvedText == nil, let range {
                guard !isCancelled() else { return nil }
                resolvedText = normalized(range.string())
                if let resolvedText, hasKnownRange {
                    return makeSnapshot(
                        text: resolvedText,
                        selectedRange: selectedRange,
                        bounds: nil,
                        sourceAppIdentifier: sourceAppIdentifier
                    )
                }
            }

            guard !isCancelled() else { return nil }
            let markerRange = candidate.selectedTextMarkerRange()

            if resolvedText == nil, let markerRange {
                guard !isCancelled() else { return nil }
                resolvedText = normalized(markerRange.string())

                if resolvedText == nil {
                    guard !isCancelled() else { return nil }
                    resolvedText = normalized(markerRange.attributedString()?.string)
                }
            }

            guard let resolvedText else {
                diagnostics.log("\(candidate.context) no selected text value")
                continue
            }

            var resolvedBounds: CGRect?
            if !hasKnownRange {
                if let range {
                    guard !isCancelled() else { return nil }
                    resolvedBounds = normalizedBounds(
                        range.bounds(),
                        normalizeBounds: normalizeBounds
                    )
                }

                if resolvedBounds == nil, let markerRange {
                    guard !isCancelled() else { return nil }
                    resolvedBounds = normalizedBounds(
                        markerRange.bounds(),
                        normalizeBounds: normalizeBounds
                    )
                }
            }

            return makeSnapshot(
                text: resolvedText,
                selectedRange: NSRange(
                    location: selectedRange.location,
                    length: selectedRange.location == NSNotFound
                        ? resolvedText.utf16.count
                        : selectedRange.length
                ),
                bounds: resolvedBounds,
                sourceAppIdentifier: sourceAppIdentifier
            )
        }

        return nil
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func isKnown(_ range: NSRange) -> Bool {
        range.location != NSNotFound && range.length > 0
    }

    private static func normalizedBounds(
        _ bounds: CGRect?,
        normalizeBounds: (CGRect) -> CGRect
    ) -> CGRect? {
        guard let bounds else { return nil }
        let normalized = normalizeBounds(bounds)
        guard normalized.width > 0, normalized.height > 0 else { return nil }
        return normalized
    }

    private static func makeSnapshot(
        text: String,
        selectedRange: NSRange,
        bounds: CGRect?,
        sourceAppIdentifier: String?
    ) -> SelectedTextSnapshot {
        SelectedTextSnapshot(
            text: text,
            selectedRange: selectedRange,
            bounds: bounds,
            sourceAppIdentifier: sourceAppIdentifier
        )
    }
}
