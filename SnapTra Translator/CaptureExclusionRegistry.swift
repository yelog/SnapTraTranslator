import AppKit
import Foundation

@MainActor
final class CaptureExclusionRegistry {
    static let shared = CaptureExclusionRegistry()

    private var windowNumbers = Set<Int>()

    private init() {}

    func register(_ window: NSWindow) {
        let windowNumber = window.windowNumber
        guard windowNumber > 0 else { return }
        windowNumbers.insert(windowNumber)
    }

    func registeredWindowNumbers() -> Set<Int> {
        windowNumbers
    }

    nonisolated static func excludedWindowNumbers(
        registeredWindowNumbers: Set<Int>,
        visibleWindowNumbers: [Int]
    ) -> Set<Int> {
        Set(visibleWindowNumbers.filter { registeredWindowNumbers.contains($0) })
    }
}
