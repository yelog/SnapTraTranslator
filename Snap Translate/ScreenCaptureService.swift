import AppKit
import Foundation
import ScreenCaptureKit

struct CaptureRegion {
    var rect: CGRect
    var screen: NSScreen
    var displayID: CGDirectDisplayID
}

final class ScreenCaptureService {
    let captureSize = CGSize(width: 260, height: 140)

    func captureAroundCursor() async -> (image: CGImage, region: CaptureRegion)? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else {
            return nil
        }
        guard let displayNumber = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(displayNumber.int32Value)
        let rectInScreen = captureRect(for: mouseLocation, in: screen.frame, size: captureSize)
        let cgRect = convertToQuartzCoordinates(rectInScreen, screen: screen, displayID: displayID)

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                return nil
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = makeConfiguration(for: cgRect)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return (image, CaptureRegion(rect: rectInScreen, screen: screen, displayID: displayID))
        } catch {
            return nil
        }
    }

    private func captureRect(for point: CGPoint, in screenFrame: CGRect, size: CGSize) -> CGRect {
        let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        let rawRect = CGRect(origin: origin, size: size)
        return rawRect.intersection(screenFrame)
    }

    private func convertToQuartzCoordinates(_ rect: CGRect, screen: NSScreen, displayID: CGDirectDisplayID) -> CGRect {
        let displayBounds = CGDisplayBounds(displayID)
        let screenFrame = screen.frame
        let localX = rect.minX - screenFrame.minX
        let localY = rect.minY - screenFrame.minY
        let cgX = displayBounds.minX + localX
        let cgY = displayBounds.minY + displayBounds.height - (localY + rect.height)
        return CGRect(x: cgX, y: cgY, width: rect.width, height: rect.height)
    }

    private func makeConfiguration(for rect: CGRect) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = Int(rect.width)
        configuration.height = Int(rect.height)
        configuration.queueDepth = 1
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        return configuration
    }
}
