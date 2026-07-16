import CoreGraphics
import Foundation

nonisolated struct ScreenCaptureCacheKey: Equatable, Hashable, Sendable {
    let exclusionGeneration: UInt64
    let explicitInvalidationEpoch: UInt64
}

nonisolated enum ScreenCaptureContentCacheSource: Equatable, Sendable {
    case cacheHit
    case cacheMiss
}

nonisolated struct ScreenCaptureContentCacheResult<Value: Sendable>: Sendable {
    let value: Value
    let source: ScreenCaptureContentCacheSource
}

nonisolated struct ScreenCaptureRefreshBudget: Equatable, Sendable {
    let maximumRefreshCount: Int
    private(set) var consumedRefreshCount = 0

    init(maximumRefreshCount: Int = 1) {
        self.maximumRefreshCount = max(maximumRefreshCount, 0)
    }

    mutating func consumeRefresh() -> Bool {
        guard consumedRefreshCount < maximumRefreshCount else { return false }
        consumedRefreshCount += 1
        return true
    }
}

nonisolated struct ScreenCaptureMetadataSnapshot<Display, Window>: @unchecked Sendable {
    private let displaysByID: [CGDirectDisplayID: Display]
    private let windowEntries: [(number: Int, window: Window)]

    init(
        displays: [(id: CGDirectDisplayID, display: Display)],
        windows: [(number: Int, window: Window)]
    ) {
        var displaysByID: [CGDirectDisplayID: Display] = [:]
        for entry in displays {
            displaysByID[entry.id] = entry.display
        }
        self.displaysByID = displaysByID
        self.windowEntries = windows
    }

    func display(for displayID: CGDirectDisplayID) -> Display? {
        displaysByID[displayID]
    }

    func windows(withNumbers windowNumbers: Set<Int>) -> [Window] {
        windowEntries.compactMap { entry in
            windowNumbers.contains(entry.number) ? entry.window : nil
        }
    }
}

nonisolated final class ScreenCaptureContentCache<Value: Sendable>: @unchecked Sendable {
    typealias Loader = @Sendable () async throws -> Value

    private struct Entry {
        let key: ScreenCaptureCacheKey
        let value: Value
    }

    private struct InFlightLoad {
        let token: UInt64
        let task: Task<Value, Error>
    }

    private enum PreparedContent {
        case cached(Value)
        case loading(
            key: ScreenCaptureCacheKey,
            token: UInt64,
            task: Task<Value, Error>
        )
    }

    private let loader: Loader
    private let lock = NSLock()
    private var explicitInvalidationEpoch: UInt64 = 0
    private var latestExclusionGeneration: UInt64 = 0
    private var nextLoadToken: UInt64 = 0
    private var entry: Entry?
    private var inFlightLoads: [ScreenCaptureCacheKey: InFlightLoad] = [:]

    init(loader: @escaping Loader) {
        self.loader = loader
    }

    func content(
        exclusionGeneration: UInt64
    ) async throws -> ScreenCaptureContentCacheResult<Value> {
        let prepared = prepareContent(exclusionGeneration: exclusionGeneration)

        switch prepared {
        case .cached(let value):
            return ScreenCaptureContentCacheResult(value: value, source: .cacheHit)
        case .loading(let key, let token, let task):
            do {
                let value = try await task.value
                guard completeLoad(value, key: key, token: token) else {
                    throw CancellationError()
                }
                try Task.checkCancellation()
                return ScreenCaptureContentCacheResult(value: value, source: .cacheMiss)
            } catch {
                failLoad(key: key, token: token)
                throw error
            }
        }
    }

    func resolvedContent<Resolved: Sendable>(
        exclusionGeneration: UInt64,
        refreshBudget: inout ScreenCaptureRefreshBudget,
        resolving resolver: @Sendable (Value) -> Resolved?
    ) async throws -> ScreenCaptureContentCacheResult<Resolved>? {
        while true {
            let result = try await content(exclusionGeneration: exclusionGeneration)
            if let resolved = resolver(result.value) {
                return ScreenCaptureContentCacheResult(
                    value: resolved,
                    source: result.source
                )
            }

            guard refreshBudget.consumeRefresh() else { return nil }
            invalidate()
        }
    }

    func invalidate() {
        let tasksToCancel: [Task<Value, Error>]

        lock.lock()
        explicitInvalidationEpoch &+= 1
        entry = nil
        tasksToCancel = inFlightLoads.values.map(\.task)
        inFlightLoads.removeAll()
        lock.unlock()

        tasksToCancel.forEach { $0.cancel() }
    }

    private func prepareContent(exclusionGeneration: UInt64) -> PreparedContent {
        lock.lock()
        defer { lock.unlock() }

        if exclusionGeneration > latestExclusionGeneration {
            latestExclusionGeneration = exclusionGeneration
            if entry?.key.exclusionGeneration != exclusionGeneration {
                entry = nil
            }
        }

        let key = ScreenCaptureCacheKey(
            exclusionGeneration: exclusionGeneration,
            explicitInvalidationEpoch: explicitInvalidationEpoch
        )
        if let entry, entry.key == key {
            return .cached(entry.value)
        }
        if let inFlightLoad = inFlightLoads[key] {
            return .loading(
                key: key,
                token: inFlightLoad.token,
                task: inFlightLoad.task
            )
        }

        nextLoadToken &+= 1
        let token = nextLoadToken
        let loader = self.loader
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try await loader()
        }
        inFlightLoads[key] = InFlightLoad(token: token, task: task)
        return .loading(key: key, token: token, task: task)
    }

    private func completeLoad(
        _ value: Value,
        key: ScreenCaptureCacheKey,
        token: UInt64
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let currentKey = ScreenCaptureCacheKey(
            exclusionGeneration: latestExclusionGeneration,
            explicitInvalidationEpoch: explicitInvalidationEpoch
        )
        guard key == currentKey else { return false }

        if inFlightLoads[key]?.token != token {
            return entry?.key == key
        }

        inFlightLoads.removeValue(forKey: key)
        entry = Entry(key: key, value: value)
        return true
    }

    private func failLoad(key: ScreenCaptureCacheKey, token: UInt64) {
        lock.lock()
        defer { lock.unlock() }

        guard inFlightLoads[key]?.token == token else { return }
        inFlightLoads.removeValue(forKey: key)
    }
}
