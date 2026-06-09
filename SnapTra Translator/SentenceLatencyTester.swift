//
//  SentenceLatencyTester.swift
//  SnapTra Translator
//
//  Latency testing for sentence translation services.
//

import Combine
import Foundation

/// Manages latency testing for sentence translation sources.
@MainActor
final class SentenceLatencyTester: ObservableObject {
    enum LatencyResult: Equatable {
        case pending
        case testing
        case success(TimeInterval)  // milliseconds
        case failed(String?)  // Optional error message for tooltip
        case local  // For offline/native sources
    }

    @Published var latencies: [SentenceTranslationSource.SourceType: LatencyResult] = [:]
    @Published var isTesting = false

    private let service: SentenceTranslationService
    private let session: URLSession
    private let timeout: TimeInterval = 5.0

    init(service: SentenceTranslationService? = nil, session: URLSession? = nil) {
        self.service = service ?? SentenceTranslationService()
        self.session = session ?? SharedURLSession.ephemeral
    }

    /// Test enabled sentence translation sources.
    func testAll(
        sources: [SentenceTranslationSource] = [],
        configurations: [LLMProviderConfiguration] = []
    ) async {
        guard !isTesting else { return }
        isTesting = true
        defer { isTesting = false }

        let testTypes = resolvedTestTypes(from: sources)
        guard !testTypes.isEmpty else { return }

        // Reset to testing state
        for type in testTypes {
            latencies[type] = .testing
        }

        // Test sequentially to avoid rate limiting
        for type in testTypes {
            let configuration = configurations.first { $0.provider == type }
            let result = await testLatency(for: type, configuration: configuration)
            self.latencies[type] = result
            // Small delay between tests to avoid rate limiting
            if type != testTypes.last {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    /// Test latency for a specific sentence translation source.
    private func testLatency(
        for type: SentenceTranslationSource.SourceType,
        configuration: LLMProviderConfiguration?
    ) async -> LatencyResult {
        switch type {
        case .native:
            return .local
        case .google, .bing, .youdao, .openAI, .anthropic, .gemini, .deepSeek, .zhipu, .ollama, .omlx:
            return await testThirdPartyService(type: type, configuration: configuration)
        }
    }

    private func testThirdPartyService(
        type: SentenceTranslationSource.SourceType,
        configuration: LLMProviderConfiguration?
    ) async -> LatencyResult {
        let testText = "hello"
        let sourceLanguage = "en"
        let targetLanguage = "zh-Hans"

        let startTime = Date()

        do {
            let result = try await withTimeout(seconds: timeout) { [self] in
                try await service.translate(
                    text: testText,
                    provider: type,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    llmConfiguration: configuration
                )
            }

            guard let translation = result, !translation.isEmpty else {
                return .failed(String(localized: "Empty response"))
            }

            let elapsed = Date().timeIntervalSince(startTime) * 1000  // Convert to ms
            return .success(elapsed)

        } catch is TimeoutError {
            return .failed(String(localized: "Request timeout"))
        } catch let error as SentenceTranslationError {
            let message = error.localizedDescription
            return .failed(message)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func resolvedTestTypes(
        from sources: [SentenceTranslationSource]
    ) -> [SentenceTranslationSource.SourceType] {
        guard !sources.isEmpty else {
            return [.google, .bing, .youdao]
        }

        let regularTypes = sources
            .filter { !$0.isNative && !$0.type.isLLMProvider }
            .map(\.type)
        let enabledLLMTypes = sources
            .filter { $0.isEnabled && $0.type.isLLMProvider }
            .map(\.type)

        return regularTypes + enabledLLMTypes
    }

    private struct TimeoutError: Error {}

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            return result
        }
    }
}
