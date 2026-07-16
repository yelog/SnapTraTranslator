import AVFoundation
import Foundation
import XCTest
@testable import SnapTra_Translator

@MainActor
final class SpeechServiceTests: XCTestCase {
    override func tearDown() {
        CancellationObservingURLProtocol.reset()
        super.tearDown()
    }

    func testCurrentOnlineSuccessPlaysReturnedAudioOnly() async {
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: nil)

        service.speak("first", language: "en", provider: .youdao)
        await waitUntil { fetcher.requestCount == 1 }
        let audio = Data([0x49, 0x44, 0x33, 0x01])
        fetcher.succeedRequest(at: 0, with: audio)

        await waitUntil { output.onlineAudio == [audio] }
        XCTAssertEqual(output.appleTexts, [])
    }

    func testCurrentOnlineFailureFallsBackToAppleOnce() async {
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: nil)

        service.speak("fallback", language: "en", provider: .google)
        await waitUntil { fetcher.requestCount == 1 }
        fetcher.failRequest(at: 0, with: TestError.failed)

        await waitUntil { output.appleTexts == ["fallback"] }
        XCTAssertEqual(output.appleTexts.count, 1)
        XCTAssertTrue(output.onlineAudio.isEmpty)
    }

    func testPlaybackRejectionFallsBackToAppleOnce() async {
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        output.playOnlineResult = false
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: nil)

        service.speak("fallback", language: "en", provider: .google)
        await waitUntil { fetcher.requestCount == 1 }
        fetcher.succeedRequest(at: 0, with: Data([0x49, 0x44, 0x33, 0x01]))

        await waitUntil { output.appleTexts == ["fallback"] }
        XCTAssertEqual(output.playOnlineCallCount, 1)
    }

    func testPlaybackCancellationNeverFallsBackToApple() async {
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        output.playOnlineError = CancellationError()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: nil)

        service.speak("cancelled", language: "en", provider: .google)
        await waitUntil { fetcher.requestCount == 1 }
        fetcher.succeedRequest(at: 0, with: Data([0x49, 0x44, 0x33, 0x01]))

        await waitUntil { output.playOnlineCallCount == 1 }
        await drainMainActor()
        XCTAssertTrue(output.appleTexts.isEmpty)
    }

    func testSecondSpeakCancelsFirstFetchTask() async {
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: nil)

        service.speak("A", language: "en", provider: .youdao)
        await waitUntil { fetcher.requestCount == 1 }
        service.speak("B", language: "en", provider: .baidu)

        await waitUntil { fetcher.cancelledRequestIndices.contains(0) }
        XCTAssertEqual(fetcher.requestCount, 2)
    }

    func testStopSpeakingCancelsActiveFetchTask() async {
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: nil)

        service.speak("A", language: "en", provider: .youdao)
        await waitUntil { fetcher.requestCount == 1 }
        service.stopSpeaking()

        await waitUntil { fetcher.cancelledRequestIndices.contains(0) }
        XCTAssertTrue(output.onlineAudio.isEmpty)
        XCTAssertTrue(output.appleTexts.isEmpty)
    }

    func testStaleSuccessCannotPlay() async {
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: nil)

        service.speak("A", language: "en", provider: .youdao)
        await waitUntil { fetcher.requestCount == 1 }
        service.speak("B", language: "en", provider: .google)
        await waitUntil { fetcher.requestCount == 2 }

        fetcher.succeedRequest(at: 0, with: Data([0x01, 0x02, 0x03, 0x04]))
        await drainMainActor()

        XCTAssertTrue(output.onlineAudio.isEmpty)
        XCTAssertTrue(output.appleTexts.isEmpty)
    }

    func testStaleErrorCannotFallbackToApple() async {
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: nil)

        service.speak("A", language: "en", provider: .youdao)
        await waitUntil { fetcher.requestCount == 1 }
        service.speak("B", language: "en", provider: .google)
        await waitUntil { fetcher.requestCount == 2 }

        fetcher.failRequest(at: 0, with: TestError.failed)
        await drainMainActor()

        XCTAssertTrue(output.appleTexts.isEmpty)
    }

    func testAppleRequestInvalidatesOlderOnlineRequest() async {
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: nil)

        service.speak("online", language: "en", provider: .youdao)
        await waitUntil { fetcher.requestCount == 1 }
        service.speak("apple", language: "en", provider: .apple)
        fetcher.succeedRequest(at: 0, with: Data([0x01, 0x02, 0x03, 0x04]))

        await drainMainActor()
        XCTAssertEqual(output.appleTexts, ["apple"])
        XCTAssertTrue(output.onlineAudio.isEmpty)
        XCTAssertTrue(fetcher.cancelledRequestIndices.contains(0))
    }

    func testOldCompletionCannotClearNewerActiveTask() async {
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: nil)

        service.speak("A", language: "en", provider: .youdao)
        await waitUntil { fetcher.requestCount == 1 }
        service.speak("B", language: "en", provider: .google)
        await waitUntil { fetcher.requestCount == 2 }
        fetcher.succeedRequest(at: 0, with: Data([0x01, 0x02, 0x03, 0x04]))
        await drainMainActor()

        service.stopSpeaking()
        await waitUntil { fetcher.cancelledRequestIndices.contains(1) }
        XCTAssertTrue(output.onlineAudio.isEmpty)
    }

    func testYoudaoCancellationCallsURLProtocolStopLoading() async {
        let session = makeCancellationObservingSession()
        let service = YoudaoTTSService(session: session, uncachedSession: session)
        await assertCancellationStopsLoading {
            try await service.fetchAudio(text: "word", language: "en", useAmericanAccent: true)
        }
    }

    func testBaiduCancellationCallsURLProtocolStopLoading() async {
        let session = makeCancellationObservingSession()
        let service = BaiduTTSService(session: session, uncachedSession: session)
        await assertCancellationStopsLoading {
            try await service.fetchAudio(text: "word", language: "en", useAmericanAccent: true)
        }
    }

    func testGoogleCancellationCallsURLProtocolStopLoading() async {
        let session = makeCancellationObservingSession()
        let service = GoogleTTSService(session: session, uncachedSession: session)
        await assertCancellationStopsLoading {
            try await service.fetchAudio(text: "word", language: "en", useAmericanAccent: true)
        }
    }

    func testStoppedHTTPRequestNeverFallsBackToApple() async {
        let session = makeCancellationObservingSession()
        let fetcher = YoudaoFetcher(service: YoudaoTTSService(session: session, uncachedSession: session))
        let output = SpeechAudioOutputSpy()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: nil)

        service.speak("word", language: "en", provider: .youdao)
        await waitUntil { CancellationObservingURLProtocol.didStart }
        service.stopSpeaking()

        await waitUntil { CancellationObservingURLProtocol.didStop }
        await drainMainActor()
        XCTAssertTrue(output.appleTexts.isEmpty)
    }

    func testCancellingEdgeFetchCancelsSocketAndUnblocksReceive() async {
        let socket = ControlledWebSocketTask()
        let service = EdgeTTSService(
            taskFactory: FixedWebSocketTaskFactory(task: socket),
            timeoutNanoseconds: 5_000_000_000
        )
        let task = Task {
            try await service.fetchAudio(text: "word", language: "en")
        }
        await waitUntil { socket.receiveCallCount == 1 }

        task.cancel()

        await waitUntil { socket.cancelCallCount > 0 && socket.didUnblockReceive }
        do {
            _ = try await task.value
            XCTFail("Expected Edge request cancellation")
        } catch {
            XCTAssertTrue(Self.isCancellation(error))
        }
    }

    func testEdgeTimeoutCancelsSocketBeforeThrowing() async {
        let socket = ControlledWebSocketTask()
        let service = EdgeTTSService(
            taskFactory: FixedWebSocketTaskFactory(task: socket),
            timeoutNanoseconds: 5_000_000
        )

        do {
            _ = try await service.fetchAudio(text: "word", language: "en")
            XCTFail("Expected timeout")
        } catch {
            XCTAssertGreaterThan(socket.cancelCallCount, 0)
            XCTAssertTrue(socket.didUnblockReceive)
        }
    }

    func testStoppingBingSpeechCancelsSocketWithoutFallback() async {
        let socket = ControlledWebSocketTask()
        let edge = EdgeTTSService(
            taskFactory: FixedWebSocketTaskFactory(task: socket),
            timeoutNanoseconds: 5_000_000_000
        )
        let fetcher = BingFetcher(service: BingTTSService(edgeService: edge))
        let output = SpeechAudioOutputSpy()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: nil)

        service.speak("word", language: "en", provider: .bing)
        await waitUntil { socket.receiveCallCount == 1 }
        service.stopSpeaking()

        await waitUntil { socket.cancelCallCount > 0 }
        await drainMainActor()
        XCTAssertTrue(output.appleTexts.isEmpty)
        XCTAssertTrue(output.onlineAudio.isEmpty)
    }

    func testSuccessfulEdgeFetchClosesSocket() async throws {
        let socket = ControlledWebSocketTask(
            queuedMessages: [
                .data(Self.edgeAudioFrame(Data([0x49, 0x44, 0x33, 0x01]))),
                .string("Path:turn.end"),
            ]
        )
        let service = EdgeTTSService(
            taskFactory: FixedWebSocketTaskFactory(task: socket),
            timeoutNanoseconds: 5_000_000_000
        )

        let data = try await service.fetchAudio(text: "word", language: "en")

        XCTAssertEqual(data, Data([0x49, 0x44, 0x33, 0x01]))
        XCTAssertGreaterThan(socket.cancelCallCount, 0)
    }

    func testDebugDumpIsScheduledAfterOnlinePlay() async {
        let fetcher = ControlledTTSFetcher()
        let events = OrderedEventRecorder()
        let output = SpeechAudioOutputSpy(eventRecorder: events)
        let dumper = RecordingDebugAudioDumper(eventRecorder: events)
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: dumper)

        service.speak("word", language: "en", provider: .youdao)
        await waitUntil { fetcher.requestCount == 1 }
        fetcher.succeedRequest(at: 0, with: Data([0x49, 0x44, 0x33, 0x01]))
        await waitUntil { dumper.dumpCount == 1 }

        XCTAssertEqual(events.values.prefix(2), ["play", "dump"])
    }

    func testBlockedDebugDumpDoesNotBlockSpeechService() async {
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        let dumper = RecordingDebugAudioDumper(isBlocked: true)
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: dumper)

        service.speak("word", language: "en", provider: .youdao)
        await waitUntil { fetcher.requestCount == 1 }
        fetcher.succeedRequest(at: 0, with: Data([0x49, 0x44, 0x33, 0x01]))

        await waitUntil { output.onlineAudio.count == 1 && dumper.dumpCount == 1 }
        service.stopSpeaking()
        XCTAssertGreaterThanOrEqual(output.stopCount, 2)
        dumper.unblock()
    }

    func testConcurrentDebugDumpsUseDistinctURLs() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dumper = TTSDebugAudioDumper(directory: directory)

        async let first: Void = dumper.dump(
            Data([0x01]),
            provider: .youdao,
            generation: 7
        )
        async let second: Void = dumper.dump(
            Data([0x02]),
            provider: .youdao,
            generation: 7
        )
        _ = await (first, second)

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(Set(files.map(\.lastPathComponent)).count, 2)
    }

    func testStaleRequestDoesNotCreateDebugDump() async {
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        let dumper = RecordingDebugAudioDumper()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: dumper)

        service.speak("A", language: "en", provider: .youdao)
        await waitUntil { fetcher.requestCount == 1 }
        service.speak("B", language: "en", provider: .google)
        await waitUntil { fetcher.requestCount == 2 }
        fetcher.succeedRequest(at: 0, with: Data([0x49, 0x44, 0x33, 0x01]))
        await drainMainActor()

        XCTAssertEqual(dumper.dumpCount, 0)
    }

    func testAppleDidStartAndOnlinePlayAcceptedUseSameLookupID() async {
        let sink = SpeechPerformanceEventSink()
        let reporter = LookupPerformanceReporter(eventSink: sink)
        let trace = LookupPerformanceTrace(lookupID: UUID())
        let performance = LookupPerformanceContext(reporter: reporter, trace: trace)
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: nil)
        reporter.beginLookup(trace)

        service.speak("fallback", language: "en", provider: .google, performance: performance)
        await waitUntil { fetcher.requestCount == 1 }
        fetcher.failRequest(at: 0, with: TestError.failed)
        await waitUntil { output.appleTexts == ["fallback"] }
        XCTAssertFalse(sink.events.contains { $0.stage == .ttsStart && $0.kind == .milestone })

        output.fireLatestAppleDidStart()
        await waitUntil {
            sink.audioStarts.contains {
                $0.lookupID == trace.lookupID && $0.kind == .appleDidStart
            }
        }

        XCTAssertTrue(
            sink.events
                .filter { $0.stage == .ttsFetch || $0.stage == .ttsStart }
                .allSatisfy { $0.lookupID == trace.lookupID }
        )

        let onlineTrace = LookupPerformanceTrace(lookupID: UUID())
        let onlinePerformance = LookupPerformanceContext(reporter: reporter, trace: onlineTrace)
        reporter.beginLookup(onlineTrace)
        service.speak(
            "online",
            language: "en",
            provider: .google,
            performance: onlinePerformance
        )
        await waitUntil { fetcher.requestCount == 2 }
        fetcher.succeedRequest(at: 1, with: Data([0x49, 0x44, 0x33, 0x01]))
        await waitUntil {
            sink.audioStarts.contains {
                $0.lookupID == onlineTrace.lookupID && $0.kind == .playAccepted
            }
        }

        XCTAssertTrue(
            sink.events
                .filter {
                    $0.lookupID == onlineTrace.lookupID
                        && ($0.stage == .ttsFetch || $0.stage == .ttsStart)
                }
                .allSatisfy { $0.lookupID == onlineTrace.lookupID }
        )
    }

    func testOneHundredReverseCompletionsNeverPlayOrFallbackStaleRequests() async {
        let fetcher = ControlledTTSFetcher()
        let output = SpeechAudioOutputSpy()
        let dumper = RecordingDebugAudioDumper()
        let service = SpeechService(fetcher: fetcher, output: output, debugDumper: dumper)

        for index in 0..<100 {
            service.speak("A\(index)", language: "en", provider: .youdao)
            await waitUntil { fetcher.requestCount == (index * 2) + 1 }
            service.speak("B\(index)", language: "en", provider: .google)
            await waitUntil { fetcher.requestCount == (index * 2) + 2 }

            if index.isMultiple(of: 2) {
                let currentAudio = Data([0x49, UInt8(index), 0x42, 0x01])
                fetcher.succeedRequest(at: (index * 2) + 1, with: currentAudio)
                await waitUntil { output.onlineAudio.count == (index / 2) + 1 }
                let staleAudio = Data([0x49, UInt8(index), 0x41, 0x01])
                fetcher.succeedRequest(at: index * 2, with: staleAudio)
            } else {
                fetcher.failRequest(at: (index * 2) + 1, with: TestError.failed)
                await waitUntil { output.appleTexts.count == (index / 2) + 1 }
                fetcher.failRequest(at: index * 2, with: TestError.failed)
            }
            service.stopSpeaking()
            output.fireLatestAppleDidStart()
        }
        await waitUntil { dumper.dumpCount == 50 }
        await drainMainActor(iterations: 20)

        XCTAssertEqual(output.onlineAudio.count, 50)
        XCTAssertTrue(output.onlineAudio.allSatisfy { $0.count > 2 && $0[2] == 0x42 })
        XCTAssertEqual(output.appleTexts.count, 50)
        XCTAssertTrue(output.appleTexts.allSatisfy { $0.hasPrefix("B") })
        XCTAssertEqual(dumper.dumpCount, 50)
        XCTAssertEqual(output.appleDidStartCount, 0)
    }

    private func assertCancellationStopsLoading(
        operation: @escaping @MainActor () async throws -> Data
    ) async {
        CancellationObservingURLProtocol.reset()
        let task = Task { try await operation() }
        await waitUntil { CancellationObservingURLProtocol.didStart }
        task.cancel()
        await waitUntil { CancellationObservingURLProtocol.didStop }

        do {
            _ = try await task.value
            XCTFail("Expected URLSession cancellation")
        } catch {
            XCTAssertTrue(Self.isCancellation(error), "Unexpected error: \(error)")
        }
    }

    private func makeCancellationObservingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CancellationObservingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(condition(), "Condition was not met before timeout")
    }

    private func drainMainActor(iterations: Int = 5) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    private nonisolated static func edgeAudioFrame(_ audio: Data) -> Data {
        let header = Data("Path:audio\r\n".utf8)
        var frame = Data([UInt8((header.count >> 8) & 0xFF), UInt8(header.count & 0xFF)])
        frame.append(header)
        frame.append(audio)
        return frame
    }

    private nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

private enum TestError: Error {
    case failed
}

@MainActor
private final class ControlledTTSFetcher: TTSServiceFetching {
    private struct Request {
        let continuation: CheckedContinuation<Data, Error>
    }

    private var requests: [Request] = []
    private(set) var cancelledRequestIndices: Set<Int> = []

    var requestCount: Int { requests.count }

    func fetchAudio(
        text: String,
        language: String?,
        provider: TTSProvider,
        useAmericanAccent: Bool,
        disableCache: Bool
    ) async throws -> Data {
        let index = requests.count
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                requests.append(Request(continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelledRequestIndices.insert(index)
            }
        }
    }

    func succeedRequest(at index: Int, with data: Data) {
        requests[index].continuation.resume(returning: data)
    }

    func failRequest(at index: Int, with error: Error) {
        requests[index].continuation.resume(throwing: error)
    }
}

@MainActor
private final class SpeechAudioOutputSpy: SpeechAudioOutput, SpeechAudioStartObserving {
    private let eventRecorder: OrderedEventRecorder?
    private var configuredAppleStartHandler: (@MainActor () -> Void)?
    private var appleStartHandlers: [@MainActor () -> Void] = []
    var playOnlineResult = true
    var playOnlineError: Error?
    private(set) var stopCount = 0
    private(set) var appleTexts: [String] = []
    private(set) var onlineAudio: [Data] = []
    private(set) var appleDidStartCount = 0
    private(set) var playOnlineCallCount = 0

    init(eventRecorder: OrderedEventRecorder? = nil) {
        self.eventRecorder = eventRecorder
    }

    func stop() {
        stopCount += 1
        configuredAppleStartHandler = nil
        appleStartHandlers.removeAll()
    }

    func playApple(text: String, language: String?) {
        appleTexts.append(text)
        if let configuredAppleStartHandler {
            appleStartHandlers.append(configuredAppleStartHandler)
        }
        configuredAppleStartHandler = nil
    }

    func playOnlineAudio(_ data: Data) throws -> Bool {
        playOnlineCallCount += 1
        if let playOnlineError { throw playOnlineError }
        onlineAudio.append(data)
        eventRecorder?.append("play")
        return playOnlineResult
    }

    func setAppleDidStartHandler(_ handler: @escaping @MainActor () -> Void) {
        configuredAppleStartHandler = handler
    }

    func fireLatestAppleDidStart() {
        guard let handler = appleStartHandlers.popLast() else { return }
        appleDidStartCount += 1
        handler()
    }
}

@MainActor
private final class YoudaoFetcher: TTSServiceFetching {
    let service: YoudaoTTSService

    init(service: YoudaoTTSService) {
        self.service = service
    }

    func fetchAudio(
        text: String,
        language: String?,
        provider: TTSProvider,
        useAmericanAccent: Bool,
        disableCache: Bool
    ) async throws -> Data {
        try await service.fetchAudio(
            text: text,
            language: language,
            useAmericanAccent: useAmericanAccent,
            disableCache: disableCache
        )
    }
}

@MainActor
private final class BingFetcher: TTSServiceFetching {
    let service: BingTTSService

    init(service: BingTTSService) {
        self.service = service
    }

    func fetchAudio(
        text: String,
        language: String?,
        provider: TTSProvider,
        useAmericanAccent: Bool,
        disableCache: Bool
    ) async throws -> Data {
        try await service.fetchAudio(
            text: text,
            language: language,
            useAmericanAccent: useAmericanAccent,
            disableCache: disableCache
        )
    }
}

private final class CancellationObservingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var started = false
    private static var stopped = false

    static var didStart: Bool {
        lock.withLock { started }
    }

    static var didStop: Bool {
        lock.withLock { stopped }
    }

    static func reset() {
        lock.withLock {
            started = false
            stopped = false
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.started = true }
    }

    override func stopLoading() {
        Self.lock.withLock { Self.stopped = true }
    }
}

private final class ControlledWebSocketTask: TTSWebSocketTasking, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [URLSessionWebSocketTask.Message]
    private var receiveContinuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    private var _receiveCallCount = 0
    private var _cancelCallCount = 0
    private var _didUnblockReceive = false

    init(queuedMessages: [URLSessionWebSocketTask.Message] = []) {
        messages = queuedMessages
    }

    var receiveCallCount: Int { lock.withLock { _receiveCallCount } }
    var cancelCallCount: Int { lock.withLock { _cancelCallCount } }
    var didUnblockReceive: Bool { lock.withLock { _didUnblockReceive } }

    func resume() {}

    func send(_ message: URLSessionWebSocketTask.Message) async throws {}

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                _receiveCallCount += 1
                if !messages.isEmpty {
                    continuation.resume(returning: messages.removeFirst())
                } else {
                    receiveContinuation = continuation
                }
            }
        }
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let continuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>? = lock.withLock {
            _cancelCallCount += 1
            let pending = receiveContinuation
            receiveContinuation = nil
            if pending != nil {
                _didUnblockReceive = true
            }
            return pending
        }
        continuation?.resume(throwing: CancellationError())
    }
}

private struct FixedWebSocketTaskFactory: TTSWebSocketTaskCreating {
    let task: ControlledWebSocketTask

    func makeTask(for request: URLRequest) -> any TTSWebSocketTasking {
        task
    }
}

private final class OrderedEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] { lock.withLock { storage } }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

private final class RecordingDebugAudioDumper: TTSDebugAudioDumping, @unchecked Sendable {
    private let lock = NSLock()
    private let eventRecorder: OrderedEventRecorder?
    private var isBlocked: Bool
    private var unblockContinuations: [CheckedContinuation<Void, Never>] = []
    private var storedDumpCount = 0

    init(eventRecorder: OrderedEventRecorder? = nil, isBlocked: Bool = false) {
        self.eventRecorder = eventRecorder
        self.isBlocked = isBlocked
    }

    var dumpCount: Int { lock.withLock { storedDumpCount } }

    func dump(_ data: Data, provider: TTSProvider, generation: UInt64) async {
        let shouldBlock = lock.withLock {
            storedDumpCount += 1
            return isBlocked
        }
        eventRecorder?.append("dump")
        if shouldBlock {
            await withCheckedContinuation { continuation in
                let shouldResumeImmediately = lock.withLock {
                    guard isBlocked else { return true }
                    unblockContinuations.append(continuation)
                    return false
                }
                if shouldResumeImmediately {
                    continuation.resume()
                }
            }
        }
    }

    func unblock() {
        let continuations = lock.withLock {
            isBlocked = false
            let pending = unblockContinuations
            unblockContinuations.removeAll()
            return pending
        }
        continuations.forEach { $0.resume() }
    }
}

private final class SpeechPerformanceEventSink: LookupPerformanceEventSinking, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LookupPerformanceEvent] = []
    private var audioStartStorage: [LookupPerformanceAudioStartMetadata] = []

    var events: [LookupPerformanceEvent] { lock.withLock { storage } }
    var audioStarts: [LookupPerformanceAudioStartMetadata] {
        lock.withLock { audioStartStorage }
    }

    func record(_ event: LookupPerformanceEvent) {
        lock.withLock { storage.append(event) }
    }

    func recordRoute(_ route: LookupPerformanceRoute, lookupID: UUID) {}

    func recordAudioStart(_ metadata: LookupPerformanceAudioStartMetadata) {
        lock.withLock { audioStartStorage.append(metadata) }
    }
}
