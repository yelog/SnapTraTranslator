import XCTest
@testable import SnapTra_Translator

@MainActor
final class CaptureExclusionRegistryTests: XCTestCase {
    func testRegisteringNewWindowNumberAdvancesGeneration() {
        let registry = CaptureExclusionRegistry()

        registry.register(windowNumber: 101)

        XCTAssertEqual(registry.snapshot().generation, 1)
    }

    func testRegisteringSameWindowNumberDoesNotAdvanceGeneration() {
        let registry = CaptureExclusionRegistry()

        registry.register(windowNumber: 101)
        registry.register(windowNumber: 101)

        XCTAssertEqual(registry.snapshot().generation, 1)
    }

    func testSnapshotReturnsGenerationAndWindowNumbersAtomically() {
        let registry = CaptureExclusionRegistry()
        registry.register(windowNumber: 101)
        registry.register(windowNumber: 303)

        XCTAssertEqual(
            registry.snapshot(),
            CaptureExclusionSnapshot(
                generation: 2,
                windowNumbers: [101, 303]
            )
        )
    }

    func testInvalidWindowNumberDoesNotAdvanceGeneration() {
        let registry = CaptureExclusionRegistry()

        registry.register(windowNumber: 0)
        registry.register(windowNumber: -1)

        XCTAssertEqual(
            registry.snapshot(),
            CaptureExclusionSnapshot(generation: 0, windowNumbers: [])
        )
    }

    func testOnlyRegisteredWindowsRemainExcluded() {
        let registry = CaptureExclusionRegistry()
        registry.register(windowNumber: 101)
        registry.register(windowNumber: 303)

        let excluded = CaptureExclusionRegistry.excludedWindowNumbers(
            registeredWindowNumbers: registry.snapshot().windowNumbers,
            visibleWindowNumbers: [101, 202, 303, 404]
        )

        XCTAssertEqual(excluded, [101, 303])
    }

    func testExcludedWindowNumbersIncludeOnlyRegisteredVisibleWindows() {
        let excluded = CaptureExclusionRegistry.excludedWindowNumbers(
            registeredWindowNumbers: [101, 303],
            visibleWindowNumbers: [101, 202, 303, 404]
        )

        XCTAssertEqual(excluded, [101, 303])
    }

    func testExcludedWindowNumbersDoNotExcludeUnregisteredSameAppWindows() {
        let settingsWindowNumber = 202

        let excluded = CaptureExclusionRegistry.excludedWindowNumbers(
            registeredWindowNumbers: [101],
            visibleWindowNumbers: [101, settingsWindowNumber]
        )

        XCTAssertEqual(excluded, [101])
        XCTAssertFalse(excluded.contains(settingsWindowNumber))
    }

    func testExcludedWindowNumbersAreEmptyWhenNoOverlayWindowsAreRegistered() {
        let excluded = CaptureExclusionRegistry.excludedWindowNumbers(
            registeredWindowNumbers: [],
            visibleWindowNumbers: [101, 202]
        )

        XCTAssertTrue(excluded.isEmpty)
    }
}

final class ScreenCaptureContentCacheTests: XCTestCase {
    func testSameKeySequentialRequestsLoadOnce() async throws {
        let loader = CountingCacheLoader(values: [11])
        let cache = ScreenCaptureContentCache<Int> {
            await loader.load()
        }

        let first = try await cache.content(exclusionGeneration: 0)
        let second = try await cache.content(exclusionGeneration: 0)

        XCTAssertEqual(first.value, 11)
        XCTAssertEqual(first.source, .cacheMiss)
        XCTAssertEqual(second.value, 11)
        XCTAssertEqual(second.source, .cacheHit)
        let loadCount = await loader.callCount
        XCTAssertEqual(loadCount, 1)
    }

    func testSameKeyConcurrentRequestsShareOneLoad() async throws {
        let loader = SuspendedCacheLoader()
        let cache = ScreenCaptureContentCache<Int> {
            await loader.load()
        }

        let first = Task {
            try await cache.content(exclusionGeneration: 0)
        }
        await loader.waitUntilStarted()
        let second = Task {
            try await cache.content(exclusionGeneration: 0)
        }
        for _ in 0..<10 {
            await Task.yield()
        }

        let inFlightLoadCount = await loader.callCount
        XCTAssertEqual(inFlightLoadCount, 1)
        await loader.resumeAll(returning: 17)

        let firstResult = try await first.value
        let secondResult = try await second.value
        XCTAssertEqual(firstResult.value, 17)
        XCTAssertEqual(secondResult.value, 17)
        XCTAssertEqual(firstResult.source, .cacheMiss)
        XCTAssertEqual(secondResult.source, .cacheMiss)
        let finalLoadCount = await loader.callCount
        XCTAssertEqual(finalLoadCount, 1)
    }

    func testRegistryGenerationChangeReloadsOnce() async throws {
        let loader = CountingCacheLoader(values: [11, 22])
        let cache = ScreenCaptureContentCache<Int> {
            await loader.load()
        }

        _ = try await cache.content(exclusionGeneration: 0)
        _ = try await cache.content(exclusionGeneration: 0)
        let changed = try await cache.content(exclusionGeneration: 1)
        let reused = try await cache.content(exclusionGeneration: 1)

        XCTAssertEqual(changed.value, 22)
        XCTAssertEqual(changed.source, .cacheMiss)
        XCTAssertEqual(reused.value, 22)
        XCTAssertEqual(reused.source, .cacheHit)
        let loadCount = await loader.callCount
        XCTAssertEqual(loadCount, 2)
    }

    func testExplicitInvalidationEpochReloadsOnce() async throws {
        let loader = CountingCacheLoader(values: [11, 22])
        let cache = ScreenCaptureContentCache<Int> {
            await loader.load()
        }

        _ = try await cache.content(exclusionGeneration: 0)
        cache.invalidate()
        let refreshed = try await cache.content(exclusionGeneration: 0)
        let reused = try await cache.content(exclusionGeneration: 0)

        XCTAssertEqual(refreshed.value, 22)
        XCTAssertEqual(refreshed.source, .cacheMiss)
        XCTAssertEqual(reused.value, 22)
        XCTAssertEqual(reused.source, .cacheHit)
        let loadCount = await loader.callCount
        XCTAssertEqual(loadCount, 2)
    }

    func testStaleInFlightValueCannotReplaceNewGeneration() async throws {
        let loader = StaleInFlightCacheLoader()
        let cache = ScreenCaptureContentCache<Int> {
            await loader.load()
        }

        let stale = Task {
            try await cache.content(exclusionGeneration: 0)
        }
        await loader.waitUntilFirstLoadStarted()

        let current = try await cache.content(exclusionGeneration: 1)
        XCTAssertEqual(current.value, 22)
        await loader.resumeFirstLoad(returning: 11)
        do {
            _ = try await stale.value
            XCTFail("Expected the stale generation load to be cancelled")
        } catch is CancellationError {
            // Expected.
        }

        let reused = try await cache.content(exclusionGeneration: 1)
        XCTAssertEqual(reused.value, 22)
        XCTAssertEqual(reused.source, .cacheHit)
        let loadCount = await loader.callCount
        XCTAssertEqual(loadCount, 2)
    }

    func testStaleInFlightValueCannotReplaceNewInvalidationEpoch() async throws {
        let loader = StaleInFlightCacheLoader()
        let cache = ScreenCaptureContentCache<Int> {
            await loader.load()
        }

        let stale = Task {
            try await cache.content(exclusionGeneration: 0)
        }
        await loader.waitUntilFirstLoadStarted()

        cache.invalidate()
        let current = try await cache.content(exclusionGeneration: 0)
        XCTAssertEqual(current.value, 22)
        await loader.resumeFirstLoad(returning: 11)
        do {
            _ = try await stale.value
            XCTFail("Expected the invalidated load to be cancelled")
        } catch is CancellationError {
            // Expected.
        }

        let reused = try await cache.content(exclusionGeneration: 0)
        XCTAssertEqual(reused.value, 22)
        XCTAssertEqual(reused.source, .cacheHit)
        let loadCount = await loader.callCount
        XCTAssertEqual(loadCount, 2)
    }

    func testFailedLoadIsNotCached() async throws {
        let loader = FailingCacheLoader()
        let cache = ScreenCaptureContentCache<Int> {
            try await loader.load()
        }

        do {
            _ = try await cache.content(exclusionGeneration: 0)
            XCTFail("Expected the first load to fail")
        } catch FailingCacheLoader.LoadError.expected {
            // Expected.
        }

        let recovered = try await cache.content(exclusionGeneration: 0)
        XCTAssertEqual(recovered.value, 22)
        XCTAssertEqual(recovered.source, .cacheMiss)
        let loadCount = await loader.callCount
        XCTAssertEqual(loadCount, 2)
    }

    func testMissingDisplayForcesExactlyOneRefresh() async throws {
        typealias Snapshot = ScreenCaptureMetadataSnapshot<String, String>
        let loader = CountingCacheLoader(
            values: [
                Snapshot(displays: [(1, "Built-in")], windows: []),
                Snapshot(displays: [(1, "Built-in")], windows: []),
            ]
        )
        let cache = ScreenCaptureContentCache<Snapshot> {
            await loader.load()
        }
        var refreshBudget = ScreenCaptureRefreshBudget()

        let missing = try await cache.resolvedContent(
            exclusionGeneration: 0,
            refreshBudget: &refreshBudget
        ) { snapshot in
            snapshot.display(for: 2)
        }

        XCTAssertNil(missing)
        XCTAssertEqual(refreshBudget.consumedRefreshCount, 1)
        let loadCount = await loader.callCount
        XCTAssertEqual(loadCount, 2)
    }

    func testMetadataSnapshotCanResolveTwoDisplayIDs() {
        let snapshot = ScreenCaptureMetadataSnapshot<String, String>(
            displays: [
                (1, "Built-in"),
                (2, "External"),
            ],
            windows: [
                (101, "Overlay"),
                (202, "Settings"),
            ]
        )

        XCTAssertEqual(snapshot.display(for: 1), "Built-in")
        XCTAssertEqual(snapshot.display(for: 2), "External")
        XCTAssertEqual(snapshot.windows(withNumbers: [101]), ["Overlay"])
        XCTAssertNil(snapshot.display(for: 3))
    }
}

private actor CountingCacheLoader<Value: Sendable> {
    private let values: [Value]
    private(set) var callCount = 0

    init(values: [Value]) {
        precondition(!values.isEmpty)
        self.values = values
    }

    func load() -> Value {
        let index = min(callCount, values.count - 1)
        callCount += 1
        return values[index]
    }
}

private actor SuspendedCacheLoader {
    private(set) var callCount = 0
    private var continuations: [CheckedContinuation<Int, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func load() async -> Int {
        callCount += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilStarted() async {
        guard callCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeAll(returning value: Int) {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: value) }
    }
}

private actor StaleInFlightCacheLoader {
    private(set) var callCount = 0
    private var firstContinuation: CheckedContinuation<Int, Never>?
    private var firstStartWaiters: [CheckedContinuation<Void, Never>] = []

    func load() async -> Int {
        callCount += 1
        guard callCount == 1 else { return 22 }

        let waiters = firstStartWaiters
        firstStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            firstContinuation = continuation
        }
    }

    func waitUntilFirstLoadStarted() async {
        guard callCount == 0 else { return }
        await withCheckedContinuation { continuation in
            firstStartWaiters.append(continuation)
        }
    }

    func resumeFirstLoad(returning value: Int) {
        firstContinuation?.resume(returning: value)
        firstContinuation = nil
    }
}

private actor FailingCacheLoader {
    enum LoadError: Error {
        case expected
    }

    private(set) var callCount = 0

    func load() throws -> Int {
        callCount += 1
        if callCount == 1 {
            throw LoadError.expected
        }
        return 22
    }
}
