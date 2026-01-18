import Combine
import Foundation
import SwiftUI
import Translation


enum TranslationError: Error {
    case unsupportedSystem
    case emptyText
    case timeout
}

struct TranslationRequest {
    let id: UUID
    let text: String
    let source: Locale.Language?
    let target: Locale.Language
    let continuation: CheckedContinuation<String, Error>
}

@MainActor
final class TranslationBridge: ObservableObject {
    @Published var pendingRequest: TranslationRequest?

    private var requestStream: AsyncStream<TranslationRequest>
    private var requestContinuation: AsyncStream<TranslationRequest>.Continuation

    init() {
        var continuation: AsyncStream<TranslationRequest>.Continuation!
        requestStream = AsyncStream { continuation = $0 }
        requestContinuation = continuation
    }

    var requests: AsyncStream<TranslationRequest> {
        requestStream
    }

    func resetStream() {
        requestContinuation.finish()
        var continuation: AsyncStream<TranslationRequest>.Continuation!
        requestStream = AsyncStream { continuation = $0 }
        requestContinuation = continuation
    }

    func translate(text: String, source: Locale.Language?, target: Locale.Language, timeout: TimeInterval = 10.0) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyText
        }

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    let request = TranslationRequest(id: UUID(), text: trimmed, source: source, target: target, continuation: continuation)
                    Task { @MainActor in
                        self.pendingRequest = request
                        self.requestContinuation.yield(request)
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TranslationError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

@available(macOS 15.0, *)
struct TranslationBridgeView: View {
    @ObservedObject var bridge: TranslationBridge
    @ObservedObject var settings: SettingsStore
    @State private var configuration: TranslationSession.Configuration?
    @State private var configurationID = UUID()

    private var sourceLocale: Locale.Language {
        Locale.Language(identifier: settings.sourceLanguage)
    }

    private var targetLocale: Locale.Language {
        Locale.Language(identifier: settings.targetLanguage)
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                configuration = TranslationSession.Configuration(source: sourceLocale, target: targetLocale)
            }
            .onChange(of: settings.sourceLanguage) { _, _ in
                resetConfiguration()
            }
            .onChange(of: settings.targetLanguage) { _, _ in
                resetConfiguration()
            }
            .translationTask(configuration) { session in
                for await request in bridge.requests {
                    do {
                        let response = try await session.translate(request.text)
                        request.continuation.resume(returning: response.targetText)
                    } catch {
                        request.continuation.resume(throwing: error)
                    }
                    await MainActor.run {
                        bridge.pendingRequest = nil
                    }
                }
            }
            .id(configurationID)
    }

    private func resetConfiguration() {
        // Clear pending request when language changes to avoid stuck state
        if let pending = bridge.pendingRequest {
            pending.continuation.resume(throwing: CancellationError())
            bridge.pendingRequest = nil
        }
        // Reset stream so new translationTask can receive requests
        bridge.resetStream()
        // Force view recreation to ensure translationTask restarts properly
        configurationID = UUID()
        configuration = TranslationSession.Configuration(source: sourceLocale, target: targetLocale)
    }
}
