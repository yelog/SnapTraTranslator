import CoreGraphics
@preconcurrency import Dispatch
import Foundation
import OSLog
import Vision

nonisolated enum OCRRecognitionMode: String, Sendable {
    case accurate
    case fast
}

nonisolated enum OCRExecutionError: Error, Equatable {
    case timedOut(OCRRecognitionMode)
    case busy(OCRRecognitionMode)
    case unsupportedFastLanguage
}

/// Cancellation ends the caller's wait even when Vision ignores request.cancel().
/// The physical worker slot remains occupied until the framework actually exits.
nonisolated final class OCRRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var request: VNRequest?
    private var handler: (@Sendable () -> Void)?

    func cancel() {
        let (activeRequest, callback) = lock.withLock {
            guard !isCancelled else { return (nil as VNRequest?, nil as (@Sendable () -> Void)?) }
            isCancelled = true
            let callback = handler
            handler = nil
            return (request, callback)
        }
        callback?()
        activeRequest?.cancel()
    }

    func setHandler(_ callback: (@Sendable () -> Void)?) {
        let cancelled = lock.withLock {
            if !isCancelled { handler = callback }
            return isCancelled
        }
        if cancelled { callback?() }
    }

    func checkCancellation() throws {
        if lock.withLock({ isCancelled }) { throw CancellationError() }
    }

    func register(_ request: VNRequest) throws {
        let cancelled = lock.withLock {
            self.request = request
            return isCancelled
        }
        if cancelled {
            request.cancel()
            throw CancellationError()
        }
    }

    func unregister() {
        lock.withLock { request = nil }
    }
}

/// Timeout, cancellation and a late Vision result race to resume exactly once.
nonisolated private final class OCRAttemptCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[VNRecognizedTextObservation], Error>?

    init(_ continuation: CheckedContinuation<[VNRecognizedTextObservation], Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func finish(_ result: Result<[VNRecognizedTextObservation], Error>) -> Bool {
        let pending = lock.withLock {
            let pending = continuation
            continuation = nil
            return pending
        }
        pending?.resume(with: result)
        return pending != nil
    }
}

/// Each engine has one physical worker and no backlog. An abandoned accurate
/// call cannot block the fast engine or accumulate more stuck accurate calls.
nonisolated private final class OCRRecognitionLane: @unchecked Sendable {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var occupied = false

    init(mode: OCRRecognitionMode) {
        queue = DispatchQueue(label: "SnapTra.OCR.\(mode.rawValue)", qos: .userInitiated)
    }

    func run(
        mode: OCRRecognitionMode,
        timeout: TimeInterval,
        parent: OCRRequestCancellation,
        operation: @escaping @Sendable (OCRRequestCancellation) throws -> [VNRecognizedTextObservation]
    ) async throws -> [VNRecognizedTextObservation] {
        try parent.checkCancellation()
        let reserved = lock.withLock {
            guard !occupied else { return false }
            occupied = true
            return true
        }
        guard reserved else { throw OCRExecutionError.busy(mode) }
        defer { parent.setHandler(nil) }

        return try await withCheckedThrowingContinuation { continuation in
            let completion = OCRAttemptCompletion(continuation)
            let cancellation = OCRRequestCancellation()
            cancellation.setHandler { completion.finish(.failure(CancellationError())) }
            let deadline = DispatchWorkItem {
                if completion.finish(.failure(OCRExecutionError.timedOut(mode))) {
                    cancellation.cancel()
                }
            }
            parent.setHandler { cancellation.cancel() }
            queue.async {
                let result = Result {
                    try cancellation.checkCancellation()
                    let observations = try operation(cancellation)
                    try cancellation.checkCancellation()
                    return observations
                }
                deadline.cancel()
                // Release only after the physical operation exits, before waking
                // a successful caller that may immediately submit another lookup.
                self.lock.withLock { self.occupied = false }
                completion.finish(result)
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + timeout, execute: deadline
            )
        }
    }
}

nonisolated final class OCRRecognitionExecutor: @unchecked Sendable {
    typealias Recognizer = @Sendable (
        CGImage, String, OCRRecognitionMode, OCRRequestCancellation
    ) throws -> [VNRecognizedTextObservation]

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SnapTraTranslator",
        category: "OCR"
    )
    private let accurateLane = OCRRecognitionLane(mode: .accurate)
    private let fastLane = OCRRecognitionLane(mode: .fast)
    private let recognizer: Recognizer
    private let fastLanguages: @Sendable () throws -> [String]
    private let now: @Sendable () -> TimeInterval
    private let cooldown: TimeInterval
    private let accurateTimeout: TimeInterval
    private let fastTimeout: TimeInterval
    private let stateLock = NSLock()
    private var fastUntil: [String: TimeInterval] = [:]

    init(
        cooldown: TimeInterval = 60,
        accurateTimeout: TimeInterval = 1,
        fastTimeout: TimeInterval = 2,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        fastLanguages: @escaping @Sendable () throws -> [String] = {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            return try request.supportedRecognitionLanguages()
        },
        recognizer: @escaping Recognizer = { image, language, mode, cancellation in
            try OCRRecognitionExecutor.performRecognition(
                image: image, language: language, mode: mode, cancellation: cancellation
            )
        }
    ) {
        self.cooldown = cooldown
        self.accurateTimeout = accurateTimeout
        self.fastTimeout = fastTimeout
        self.now = now
        self.fastLanguages = fastLanguages
        self.recognizer = recognizer
    }

    func recognize(in image: CGImage, language: String) async throws -> [VNRecognizedTextObservation] {
        try Task.checkCancellation()
        let cancellation = OCRRequestCancellation()
        return try await withTaskCancellationHandler {
            let observations = try await recognizeWithRecovery(
                image: image, language: language, cancellation: cancellation
            )
            try Task.checkCancellation()
            try cancellation.checkCancellation()
            return observations
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func recognizeWithRecovery(
        image: CGImage,
        language: String,
        cancellation: OCRRequestCancellation
    ) async throws -> [VNRecognizedTextObservation] {
        let key = language.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-").lowercased()
        if let deadline = stateLock.withLock({ fastUntil[key] }), now() < deadline {
            return try await attempt(image, language: language, mode: .fast, cancellation: cancellation)
        }

        do {
            let observations = try await attempt(image, language: language, mode: .accurate, cancellation: cancellation)
            try cancellation.checkCancellation()
            if stateLock.withLock({ fastUntil.removeValue(forKey: key) }) != nil {
                Self.logger.notice("OCR accurate recognition recovered language=\(language, privacy: .public)")
            }
            return observations
        } catch {
            try cancellation.checkCancellation()
            guard Self.isEngineFailure(error) else { throw error }
            let accurateError = error
            let observations: [VNRecognizedTextObservation]
            do {
                observations = try await attempt(image, language: language, mode: .fast, cancellation: cancellation)
            } catch OCRExecutionError.unsupportedFastLanguage {
                throw accurateError
            }
            try cancellation.checkCancellation()
            stateLock.withLock { fastUntil[key] = now() + cooldown }
            Self.logger.notice(
                "OCR fast fallback activated language=\(language, privacy: .public) cooldown_s=\(self.cooldown, privacy: .public)"
            )
            return observations
        }
    }

    private func attempt(
        _ image: CGImage,
        language: String,
        mode: OCRRecognitionMode,
        cancellation: OCRRequestCancellation
    ) async throws -> [VNRecognizedTextObservation] {
        try cancellation.checkCancellation()
        let start = now()
        let lane = mode == .accurate ? accurateLane : fastLane
        do {
            let observations = try await lane.run(
                mode: mode,
                timeout: mode == .accurate ? accurateTimeout : fastTimeout,
                parent: cancellation
            ) { attemptCancellation in
                if mode == .fast {
                    // Query capabilities inside the bounded worker too: framework
                    // initialization must never run on the caller's executor.
                    let identifier = language.trimmingCharacters(in: .whitespacesAndNewlines)
                    let sourceCode = Locale.Language(identifier: identifier.isEmpty ? "en" : identifier)
                        .languageCode?.identifier
                    let supported = try self.fastLanguages()
                    guard let sourceCode, supported.contains(where: {
                        Locale.Language(identifier: $0).languageCode?.identifier == sourceCode
                    }) else { throw OCRExecutionError.unsupportedFastLanguage }
                }
                try attemptCancellation.checkCancellation()
                return try self.recognizer(image, language, mode, attemptCancellation)
            }
            try cancellation.checkCancellation()
            Self.logger.debug(
                "OCR attempt succeeded mode=\(mode.rawValue, privacy: .public) duration_s=\(self.now() - start, privacy: .public) observations=\(observations.count, privacy: .public)"
            )
            return observations
        } catch {
            try cancellation.checkCancellation()
            let failure = error as NSError
            let reason = (error as? OCRExecutionError).map { String(describing: $0) } ?? "frameworkError"
            Self.logger.error(
                "OCR attempt failed mode=\(mode.rawValue, privacy: .public) duration_s=\(self.now() - start, privacy: .public) domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public) reason=\(reason, privacy: .public)"
            )
            throw error
        }
    }

    static func isEngineFailure(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let failure = error as? OCRExecutionError {
            return failure == .timedOut(.accurate) || failure == .busy(.accurate)
        }
        var current = error as NSError
        // Bound traversal in case a framework supplies a cyclic underlying error.
        for _ in 0..<8 {
            if current.domain == VNErrorDomain, current.code == VNErrorCode.requestCancelled.rawValue {
                return false
            }
            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
                current = underlying
            } else {
                break
            }
        }
        return (current.domain == "TextRecognition.CRImageReaderError" && current.code == 1)
            || (current.domain == VNErrorDomain && [
                VNErrorCode.internalError.rawValue,
                VNErrorCode.operationFailed.rawValue,
            ].contains(current.code))
    }

    static func performRecognition(
        image: CGImage,
        language: String,
        mode: OCRRecognitionMode,
        cancellation: OCRRequestCancellation
    ) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = mode == .accurate ? .accurate : .fast
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = mode == .accurate
        let preferred = OCRService.preferredRecognitionLanguages(for: language)
        let supported = try request.supportedRecognitionLanguages()
        var languages: [String] = []
        for identifier in preferred {
            if let match = supported.first(where: { $0 == identifier }) ?? supported.first(where: {
                Locale.Language(identifier: $0).languageCode == Locale.Language(identifier: identifier).languageCode
            }), !languages.contains(match) {
                languages.append(match)
            }
        }
        if !languages.isEmpty { request.recognitionLanguages = languages }
        try cancellation.register(request)
        defer { cancellation.unregister() }
        try cancellation.checkCancellation()
        logger.debug(
            "OCR Vision start mode=\(mode.rawValue, privacy: .public) revision=\(request.revision, privacy: .public) width=\(image.width, privacy: .public) height=\(image.height, privacy: .public) language=\(language, privacy: .public)"
        )
        let visionImage = OCRService.normalizedImageForVision(image)
        try cancellation.checkCancellation()
        try VNImageRequestHandler(cgImage: visionImage).perform([request])
        try cancellation.checkCancellation()
        return request.results ?? []
    }
}
