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
    let captureSize = CGSize(width: 520, height: 140)

    func captureAroundCursor() async -> (image: CGImage, region: CaptureRegion)? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else {
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
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                return nil
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = makeConfiguration(for: cgRect, scaleFactor: scaleFactor)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return (image, CaptureRegion(rect: rectInScreen, screen: screen, displayID: displayID, scaleFactor: scaleFactor))
        } catch {
            return nil
        }
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

    private func makeConfiguration(for rect: CGRect, scaleFactor: CGFloat) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        let pixelWidth = Int(rect.width * scaleFactor)
        let pixelHeight = Int(rect.height * scaleFactor)
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.queueDepth = 1
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        return configuration
    }
}
