import AppKit
import Foundation

nonisolated struct CaptureExclusionSnapshot: Equatable, Sendable {
    let generation: UInt64
    let windowNumbers: Set<Int>
}

@MainActor
final class CaptureExclusionRegistry {
    static let shared = CaptureExclusionRegistry()

    private var generation: UInt64 = 0
    private var windowNumbers = Set<Int>()

    init() {}

    func register(_ window: NSWindow) {
        register(windowNumber: window.windowNumber)
    }

    func register(windowNumber: Int) {
        guard windowNumber > 0 else { return }
        guard windowNumbers.insert(windowNumber).inserted else { return }
        generation &+= 1
    }

    func snapshot() -> CaptureExclusionSnapshot {
        CaptureExclusionSnapshot(
            generation: generation,
            windowNumbers: windowNumbers
        )
    }

    nonisolated static func excludedWindowNumbers(
        registeredWindowNumbers: Set<Int>,
        visibleWindowNumbers: [Int]
    ) -> Set<Int> {
        Set(visibleWindowNumbers.filter { registeredWindowNumbers.contains($0) })
    }
}
