import CoreGraphics
import CoreText
import Vision
import XCTest
@testable import SnapTra_Translator

@MainActor
final class OCRRecognitionExecutorTests: XCTestCase {
    func testCancelledAccurateCallIgnoringCancellationDoesNotBlockNextLookup() async throws {
        let started = expectation(description: "Accurate recognizer is stalled")
        let nextFinished = expectation(description: "Next lookup finishes before stalled call returns")
        let release = DispatchSemaphore(value: 0)
        let stub = OCRRecognizerStub { call, _, _, _ in
            if call == 1 {
                started.fulfill()
                _ = release.wait(timeout: .now() + 3)
            }
            return []
        }
        let executor = stub.executor()
        let image = try makeImage()
        let first = Task { try await executor.recognize(in: image, language: "en") }
        await fulfillment(of: [started], timeout: 2)
        first.cancel()
        let next = Task {
            defer { nextFinished.fulfill() }
            return try await executor.recognize(in: image, language: "en")
        }
        await fulfillment(of: [nextFinished], timeout: 0.5)
        release.signal()
        _ = try? await first.value
        _ = try await next.value
        XCTAssertEqual(stub.modes, [.accurate, .fast])
    }

    func testEngineFailureFallsBackAndCooldownSkipsAccurateUntilRecovery() async throws {
        let stub = OCRRecognizerStub { call, _, mode, _ in
            if call == 1 && mode == .accurate { throw Self.engineFailure }
            return []
        }
        let executor = stub.executor()
        let image = try makeImage()
        _ = try await executor.recognize(in: image, language: "en")
        _ = try await executor.recognize(in: image, language: "en")
        stub.advance(by: 59)
        _ = try await executor.recognize(in: image, language: "en")
        stub.advance(by: 1)
        _ = try await executor.recognize(in: image, language: "en")
        _ = try await executor.recognize(in: image, language: "en")
        XCTAssertEqual(stub.modes, [.accurate, .fast, .fast, .fast, .accurate, .accurate])
    }

    func testFailedRecoveryProbeReentersCooldown() async throws {
        let stub = OCRRecognizerStub { _, _, mode, _ in
            if mode == .accurate { throw Self.engineFailure }
            return []
        }
        let executor = stub.executor()
        let image = try makeImage()
        _ = try await executor.recognize(in: image, language: "en-US")
        stub.advance(by: 60)
        _ = try await executor.recognize(in: image, language: "en-US")
        _ = try await executor.recognize(in: image, language: "en-US")
        XCTAssertEqual(stub.modes, [.accurate, .fast, .accurate, .fast, .fast])
    }

    func testCooldownDoesNotAffectAnotherLanguage() async throws {
        let stub = OCRRecognizerStub { _, language, mode, _ in
            if language == "en" && mode == .accurate { throw Self.engineFailure }
            return []
        }
        let executor = stub.executor()
        let image = try makeImage()
        _ = try await executor.recognize(in: image, language: "en")
        _ = try await executor.recognize(in: image, language: "fr")
        XCTAssertEqual(stub.modes, [.accurate, .fast, .accurate])
    }

    func testUnsupportedSourceNeverFallsBackToEnglish() async throws {
        for language in ["zh-Hans", "zh-Hant", "ja", "ko"] {
            let stub = OCRRecognizerStub { _, _, _, _ in throw Self.engineFailure }
            do {
                _ = try await stub.executor().recognize(in: makeImage(), language: language)
                XCTFail("Expected engine failure for \(language)")
            } catch {
                XCTAssertEqual((error as NSError).domain, Self.engineFailure.domain)
            }
            XCTAssertEqual(stub.modes, [.accurate])
        }
    }

    func testLanguageRegionCanUseSupportedFastLanguage() async throws {
        let stub = OCRRecognizerStub { _, _, mode, _ in
            if mode == .accurate { throw Self.engineFailure }
            return []
        }
        _ = try await stub.executor().recognize(in: makeImage(), language: "en-GB")
        XCTAssertEqual(stub.modes, [.accurate, .fast])
    }

    func testEmptyAccurateResultDoesNotTriggerFallback() async throws {
        let stub = OCRRecognizerStub { _, _, _, _ in [] }
        _ = try await stub.executor().recognize(in: makeImage(), language: "en")
        XCTAssertEqual(stub.modes, [.accurate])
    }

    func testUnrelatedAndCancellationErrorsDoNotTriggerFallback() async throws {
        let errors: [Error] = [
            NSError(domain: VNErrorDomain, code: VNErrorCode.invalidImage.rawValue),
            NSError(domain: VNErrorDomain, code: VNErrorCode.requestCancelled.rawValue),
            CancellationError(),
        ]
        for expected in errors {
            let stub = OCRRecognizerStub { _, _, _, _ in throw expected }
            do {
                _ = try await stub.executor().recognize(in: makeImage(), language: "en")
                XCTFail("Expected error")
            } catch {
                XCTAssertEqual(stub.modes, [.accurate])
            }
        }
    }

    func testFailedFallbackDoesNotActivateCooldown() async throws {
        let stub = OCRRecognizerStub { _, _, _, _ in throw Self.engineFailure }
        let executor = stub.executor()
        for _ in 0..<2 {
            do {
                _ = try await executor.recognize(in: makeImage(), language: "en")
                XCTFail("Expected error")
            } catch {}
        }
        XCTAssertEqual(stub.modes, [.accurate, .fast, .accurate, .fast])
    }

    func testCancellationBetweenAccurateFailureAndFallbackStopsRetry() async throws {
        let stub = OCRRecognizerStub { _, _, _, cancellation in
            cancellation.cancel()
            throw Self.engineFailure
        }
        do {
            _ = try await stub.executor().recognize(in: makeImage(), language: "en")
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(stub.modes, [.accurate])
    }

    func testActiveCancellationReachesVisionRequestAndSuppressesSuccess() async throws {
        let started = expectation(description: "Vision started")
        let release = DispatchSemaphore(value: 0)
        let request = OCRCancellationSpyRequest()
        let stub = OCRRecognizerStub { _, _, _, cancellation in
            try cancellation.register(request)
            defer { cancellation.unregister() }
            started.fulfill()
            guard release.wait(timeout: .now() + 3) == .success else { throw Self.engineFailure }
            return []
        }
        let executor = stub.executor()
        let image = try makeImage()
        let task = Task { try await executor.recognize(in: image, language: "en") }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        XCTAssertTrue(request.wasCancelled)
        release.signal()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation rather than stale success")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(stub.modes, [.accurate])
    }

    func testAccurateTimeoutFallsBackWithoutWaitingForPhysicalCallToExit() async throws {
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let stub = OCRRecognizerStub { _, _, mode, _ in
            if mode == .accurate { _ = release.wait(timeout: .now() + 3) }
            return []
        }
        let executor = stub.executor(accurateTimeout: 0.05)
        _ = try await executor.recognize(in: makeImage(), language: "en")
        XCTAssertEqual(stub.modes, [.accurate, .fast])
        XCTAssertEqual(stub.maximumConcurrentAttempts, 2)
    }

    func testStalledAccurateLaneCannotAccumulateWorkersAfterCooldown() async throws {
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let stub = OCRRecognizerStub { _, _, mode, _ in
            if mode == .accurate { _ = release.wait(timeout: .now() + 3) }
            return []
        }
        let executor = stub.executor(accurateTimeout: 0.05)
        let image = try makeImage()
        for _ in 0..<10 {
            _ = try await executor.recognize(in: image, language: "en")
            stub.advance(by: 60)
        }
        XCTAssertEqual(stub.modes.filter { $0 == .accurate }.count, 1)
        XCTAssertEqual(stub.modes.filter { $0 == .fast }.count, 10)
        XCTAssertEqual(stub.maximumConcurrentAttempts, 2)
    }

    func testUnsupportedLanguageTimesOutWithoutEnglishFallback() async throws {
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let stub = OCRRecognizerStub { _, _, _, _ in
            _ = release.wait(timeout: .now() + 3)
            return []
        }
        do {
            _ = try await stub.executor(accurateTimeout: 0.05).recognize(in: makeImage(), language: "zh-Hans")
            XCTFail("Expected accurate timeout")
        } catch {
            XCTAssertEqual(error as? OCRExecutionError, .timedOut(.accurate))
        }
        XCTAssertEqual(stub.modes, [.accurate])
    }

    func testBothStalledEnginesStayBoundedAndFailPromptly() async throws {
        let release = DispatchSemaphore(value: 0)
        defer { release.signal(); release.signal() }
        let stub = OCRRecognizerStub { _, _, _, _ in
            _ = release.wait(timeout: .now() + 3)
            return []
        }
        let executor = stub.executor(accurateTimeout: 0.05, fastTimeout: 0.05)
        let image = try makeImage()
        do {
            _ = try await executor.recognize(in: image, language: "en")
            XCTFail("Expected fast timeout")
        } catch {
            XCTAssertEqual(error as? OCRExecutionError, .timedOut(.fast))
        }
        for _ in 0..<10 {
            do {
                _ = try await executor.recognize(in: image, language: "en")
                XCTFail("Expected busy fast lane")
            } catch {
                XCTAssertEqual(error as? OCRExecutionError, .busy(.fast))
            }
        }
        XCTAssertEqual(stub.modes, [.accurate, .fast])
        XCTAssertEqual(stub.maximumConcurrentAttempts, 2)
    }

    func testCancellationFinishesBeforeUncooperativeRecognizerReturns() async throws {
        let started = expectation(description: "Recognizer started")
        let cancelled = expectation(description: "Cancellation delivered without waiting for Vision")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let stub = OCRRecognizerStub { _, _, _, _ in
            started.fulfill()
            _ = release.wait(timeout: .now() + 3)
            return []
        }
        let executor = stub.executor()
        let image = try makeImage()
        let task = Task {
            do {
                _ = try await executor.recognize(in: image, language: "en")
                XCTFail("Expected cancellation")
            } catch {
                XCTAssertTrue(error is CancellationError)
            }
            cancelled.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await fulfillment(of: [cancelled], timeout: 0.5)
        await task.value
        XCTAssertEqual(stub.modes, [.accurate])
    }

    func testLanguageCapabilityQueryIsCoveredByFastTimeout() async throws {
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let executor = OCRRecognitionExecutor(
            fastTimeout: 0.05,
            fastLanguages: {
                _ = release.wait(timeout: .now() + 3)
                return ["en-US"]
            },
            recognizer: { _, _, _, _ in throw Self.engineFailure }
        )
        do {
            _ = try await executor.recognize(in: makeImage(), language: "en")
            XCTFail("Expected metadata query timeout")
        } catch {
            XCTAssertEqual(error as? OCRExecutionError, .timedOut(.fast))
        }
    }

    func testEngineClassifierHandlesWrappedFailureAndRejectsWrappedCancellation() {
        XCTAssertTrue(OCRRecognitionExecutor.isEngineFailure(NSError(
            domain: "Wrapper", code: 1, userInfo: [NSUnderlyingErrorKey: Self.engineFailure]
        )))
        XCTAssertFalse(OCRRecognitionExecutor.isEngineFailure(NSError(
            domain: VNErrorDomain, code: VNErrorCode.operationFailed.rawValue,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: VNErrorDomain, code: VNErrorCode.requestCancelled.rawValue)]
        )))
    }

    nonisolated private static var engineFailure: NSError {
        NSError(domain: "TextRecognition.CRImageReaderError", code: 1)
    }

    private func makeImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }
}

/// Explicit integration suite, run separately from deterministic recovery tests.
@MainActor
final class OCRVisionIntegrationTests: XCTestCase {
    func testVisionRecognizesSyntheticEnglish() async throws {
        let observations = try await OCRRecognitionExecutor().recognize(in: makeTextImage(), language: "en")
        assertRecognizedHello(observations)
    }

    func testRealFastVisionRecognizesWhileAccurateWorkerIgnoresCancellation() async throws {
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let executor = OCRRecognitionExecutor(
            accurateTimeout: 0.05,
            recognizer: { image, language, mode, cancellation in
                if mode == .accurate {
                    _ = release.wait(timeout: .now() + 3)
                    return []
                }
                return try OCRRecognitionExecutor.performRecognition(
                    image: image, language: language, mode: mode, cancellation: cancellation
                )
            }
        )
        let observations = try await executor.recognize(in: makeTextImage(), language: "en")
        assertRecognizedHello(observations)
    }

    private func makeTextImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 900, height: 140, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 900, height: 140))
        context.textPosition = CGPoint(x: 30, y: 55)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 48, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        CTLineDraw(CTLineCreateWithAttributedString(
            NSAttributedString(string: "hello translation", attributes: attributes)
        ), context)
        return try XCTUnwrap(context.makeImage())
    }

    private func assertRecognizedHello(_ observations: [VNRecognizedTextObservation]) {
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(text.lowercased().contains("hello"), "Expected synthetic text to be recognized, got: \(text)")
    }
}

nonisolated private final class OCRRecognizerStub: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 0
    private var attempts: [(String, OCRRecognitionMode)] = []
    private var active = 0
    private var maximumActive = 0
    private let action: @Sendable (Int, String, OCRRecognitionMode, OCRRequestCancellation) throws -> [VNRecognizedTextObservation]

    init(action: @escaping @Sendable (Int, String, OCRRecognitionMode, OCRRequestCancellation) throws -> [VNRecognizedTextObservation]) {
        self.action = action
    }

    var modes: [OCRRecognitionMode] { lock.withLock { attempts.map(\.1) } }
    var languages: [String] { lock.withLock { attempts.map(\.0) } }
    var maximumConcurrentAttempts: Int { lock.withLock { maximumActive } }

    func advance(by seconds: TimeInterval) { lock.withLock { time += seconds } }

    func executor(accurateTimeout: TimeInterval = 1, fastTimeout: TimeInterval = 2) -> OCRRecognitionExecutor {
        OCRRecognitionExecutor(
            accurateTimeout: accurateTimeout,
            fastTimeout: fastTimeout,
            now: { self.lock.withLock { self.time } },
            fastLanguages: { ["en-US", "fr-FR", "de-DE"] },
            recognizer: { _, language, mode, cancellation in
                let call = self.lock.withLock {
                    self.attempts.append((language, mode))
                    self.active += 1
                    self.maximumActive = max(self.maximumActive, self.active)
                    return self.attempts.count
                }
                defer { self.lock.withLock { self.active -= 1 } }
                return try self.action(call, language, mode, cancellation)
            }
        )
    }
}

nonisolated private final class OCRCancellationSpyRequest: VNRequest, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var onCancel: (@Sendable () -> Void)?
    var wasCancelled: Bool { lock.withLock { cancelled } }

    override func cancel() {
        lock.withLock { cancelled = true }
        super.cancel()
        onCancel?()
    }
}
