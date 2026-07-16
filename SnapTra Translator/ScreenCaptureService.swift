import AppKit
import Foundation
import ScreenCaptureKit

struct CaptureRegion {
    var rect: CGRect
    var screen: NSScreen
    var displayID: CGDirectDisplayID
    var scaleFactor: CGFloat
}

final class ScreenCaptureService {
    private typealias ContentSnapshot = ScreenCaptureMetadataSnapshot<SCDisplay, SCWindow>

    private struct CaptureSourceMetadata: @unchecked Sendable {
        let display: SCDisplay
        let excludedWindows: [SCWindow]
    }

    let captureSize = CGSize(width: 520, height: 140)
    let paragraphCaptureScale: CGFloat = 0.6

    private let exclusionRegistry: CaptureExclusionRegistry
    private let contentCache: ScreenCaptureContentCache<ContentSnapshot>

    @MainActor
    init() {
        self.exclusionRegistry = CaptureExclusionRegistry.shared
        self.contentCache = Self.makeContentCache()
    }

    @MainActor
    init(exclusionRegistry: CaptureExclusionRegistry) {
        self.exclusionRegistry = exclusionRegistry
        self.contentCache = Self.makeContentCache()
    }

    func captureAroundCursor(
        at mouseLocation: CGPoint,
        performance: LookupPerformanceContext? = nil
    ) async -> (image: CGImage, region: CaptureRegion)? {
        guard let screen = screen(containing: mouseLocation) else {
            return nil
        }
        guard let displayNumber = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(displayNumber.int32Value)
        let scaleFactor = screen.backingScaleFactor
        let rectInScreen = captureRect(for: mouseLocation, in: screen.frame, size: captureSize)
        let cgRect = convertToDisplayLocalCoordinates(rectInScreen, screen: screen)

        do {
            let configuration = makeConfiguration(for: cgRect, scaleFactor: scaleFactor)
            guard let image = try await captureImage(
                displayID: displayID,
                configuration: configuration,
                performance: performance
            ) else {
                return nil
            }
            return (image, CaptureRegion(rect: rectInScreen, screen: screen, displayID: displayID, scaleFactor: scaleFactor))
        } catch {
            return nil
        }
    }

    func captureCurrentDisplay() async -> (image: CGImage, region: CaptureRegion)? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = screen(containing: mouseLocation) else {
            return nil
        }
        guard let displayNumber = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        let displayID = CGDirectDisplayID(displayNumber.int32Value)
        let scaleFactor = screen.backingScaleFactor
        let rectInScreen = screen.frame
        let cgRect = convertToDisplayLocalCoordinates(rectInScreen, screen: screen)

        do {
            let configuration = makeConfiguration(
                for: cgRect,
                scaleFactor: scaleFactor,
                resolutionScale: paragraphCaptureScale
            )
            guard let image = try await captureImage(
                displayID: displayID,
                configuration: configuration
            ) else {
                return nil
            }
            return (image, CaptureRegion(rect: rectInScreen, screen: screen, displayID: displayID, scaleFactor: scaleFactor))
        } catch {
            return nil
        }
    }

    func capture(rect requestedRect: CGRect) async -> (image: CGImage, region: CaptureRegion)? {
        guard requestedRect.width > 0, requestedRect.height > 0 else {
            return nil
        }

        let midpoint = CGPoint(x: requestedRect.midX, y: requestedRect.midY)
        guard let screen = screen(containing: midpoint) else {
            return nil
        }
        guard let displayNumber = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        let rectInScreen = requestedRect.intersection(screen.frame)
        guard rectInScreen.width > 1, rectInScreen.height > 1 else {
            return nil
        }

        let displayID = CGDirectDisplayID(displayNumber.int32Value)
        let scaleFactor = screen.backingScaleFactor
        let cgRect = convertToDisplayLocalCoordinates(rectInScreen, screen: screen)

        do {
            let configuration = makeConfiguration(for: cgRect, scaleFactor: scaleFactor)
            guard let image = try await captureImage(
                displayID: displayID,
                configuration: configuration
            ) else {
                return nil
            }
            return (image, CaptureRegion(rect: rectInScreen, screen: screen, displayID: displayID, scaleFactor: scaleFactor))
        } catch {
            return nil
        }
    }

    func invalidateCache() {
        contentCache.invalidate()
    }

    private func captureImage(
        displayID: CGDirectDisplayID,
        configuration: SCStreamConfiguration,
        performance: LookupPerformanceContext? = nil
    ) async throws -> CGImage? {
        var refreshBudget = ScreenCaptureRefreshBudget()

        while true {
            try Task.checkCancellation()
            performance?.begin(.captureMetadata)

            let exclusionSnapshot = await MainActor.run {
                exclusionRegistry.snapshot()
            }
            let metadata: ScreenCaptureContentCacheResult<CaptureSourceMetadata>?
            do {
                metadata = try await contentCache.resolvedContent(
                    exclusionGeneration: exclusionSnapshot.generation,
                    refreshBudget: &refreshBudget
                ) { content in
                    guard let display = content.display(for: displayID) else {
                        return nil
                    }
                    return CaptureSourceMetadata(
                        display: display,
                        excludedWindows: content.windows(
                            withNumbers: exclusionSnapshot.windowNumbers
                        )
                    )
                }
            } catch {
                performance?.end(
                    .captureMetadata,
                    outcome: Self.isCancellation(error) ? .cancelled : .failed
                )
                throw error
            }

            guard let metadata else {
                performance?.end(
                    .captureMetadata,
                    outcome: Task.isCancelled ? .cancelled : .failed
                )
                return nil
            }
            guard !Task.isCancelled else {
                performance?.end(.captureMetadata, outcome: .cancelled)
                throw CancellationError()
            }
            performance?.end(
                .captureMetadata,
                outcome: metadata.source == .cacheHit ? .cacheHit : .cacheMiss
            )

            try Task.checkCancellation()
            let filter = SCContentFilter(
                display: metadata.value.display,
                excludingWindows: metadata.value.excludedWindows
            )
            performance?.begin(.screenshot)
            do {
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                try Task.checkCancellation()
                performance?.end(.screenshot, outcome: .succeeded)
                return image
            } catch {
                let isCancellation = Self.isCancellation(error)
                performance?.end(
                    .screenshot,
                    outcome: isCancellation ? .cancelled : .failed
                )
                guard !isCancellation else { throw error }
                guard Self.isStaleCaptureSourceError(error),
                      refreshBudget.consumeRefresh() else {
                    throw error
                }
                contentCache.invalidate()
            }
        }
    }

    private static func makeContentCache() -> ScreenCaptureContentCache<ContentSnapshot> {
        ScreenCaptureContentCache {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            return ContentSnapshot(
                displays: content.displays.map { ($0.displayID, $0) },
                windows: content.windows.map { (Int($0.windowID), $0) }
            )
        }
    }

    private nonisolated static func isStaleCaptureSourceError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else { return false }
        return [-3813, -3814, -3815].contains(nsError.code)
    }

    private nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return Task.isCancelled
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
    }

    private func captureRect(for point: CGPoint, in screenFrame: CGRect, size: CGSize) -> CGRect {
        let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        let rawRect = CGRect(origin: origin, size: size)
        return rawRect.intersection(screenFrame)
    }

    private func convertToDisplayLocalCoordinates(_ rect: CGRect, screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        let localX = rect.minX - screenFrame.minX
        let localY = rect.minY - screenFrame.minY
        let flippedY = screenFrame.height - (localY + rect.height)
        return CGRect(x: localX, y: flippedY, width: rect.width, height: rect.height)
    }

    private func makeConfiguration(
        for rect: CGRect,
        scaleFactor: CGFloat,
        resolutionScale: CGFloat = 1
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        let clampedScale = max(resolutionScale, 0.1)
        let pixelWidth = max(Int(rect.width * scaleFactor * clampedScale), 1)
        let pixelHeight = max(Int(rect.height * scaleFactor * clampedScale), 1)
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.queueDepth = 1
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        return configuration
    }
}
