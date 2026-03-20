import AppKit
import Foundation
import ScreenCaptureKit

struct CaptureRegion {
    var rect: CGRect
    var screen: NSScreen
    var displayID: CGDirectDisplayID
    var scaleFactor: CGFloat
}

@MainActor
final class ScreenCaptureService {
    let captureSize = CGSize(width: 520, height: 140)
    let paragraphCaptureScale: CGFloat = 0.6

    private var cachedOwnWindows: [SCWindow] = []

    func captureAroundCursor() async -> (image: CGImage, region: CaptureRegion)? {
        let mouseLocation = NSEvent.mouseLocation
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
            let display = try await getDisplay(for: displayID)
            guard let display else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: cachedOwnWindows)
            let configuration = makeConfiguration(for: cgRect, scaleFactor: scaleFactor)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
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
            let display = try await getDisplay(for: displayID)
            guard let display else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: cachedOwnWindows)
            let configuration = makeConfiguration(
                for: cgRect,
                scaleFactor: scaleFactor,
                resolutionScale: paragraphCaptureScale
            )
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return (image, CaptureRegion(rect: rectInScreen, screen: screen, displayID: displayID, scaleFactor: scaleFactor))
        } catch {
            return nil
        }
    }

    func invalidateCache() {
        cachedOwnWindows = []
    }

    private func getDisplay(for displayID: CGDirectDisplayID) async throws -> SCDisplay? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            return nil
        }

        // Always refresh our own app's window list so that overlay panels opened
        // since the last capture are excluded immediately.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        cachedOwnWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }

        return display
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

extension ScreenCaptureService: ScreenCaptureProviding {}
