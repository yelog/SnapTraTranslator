import Combine
import Foundation
import SwiftUI
import Translation

enum TranslationError: Error {
    case unsupportedSystem
    case emptyText
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

    private let requestStream: AsyncStream<TranslationRequest>
    private let requestContinuation: AsyncStream<TranslationRequest>.Continuation

    init() {
        var continuation: AsyncStream<TranslationRequest>.Continuation!
        requestStream = AsyncStream { continuation = $0 }
        requestContinuation = continuation
    }

    var requests: AsyncStream<TranslationRequest> {
        requestStream
    }

    func translate(text: String, source: Locale.Language?, target: Locale.Language) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyText
        }
        return try await withCheckedThrowingContinuation { continuation in
            let request = TranslationRequest(id: UUID(), text: trimmed, source: source, target: target, continuation: continuation)
            pendingRequest = request
            requestContinuation.yield(request)
        }
    }
}

@available(macOS 15.0, *)
struct TranslationBridgeView: View {
    @ObservedObject var bridge: TranslationBridge
    let sourceLanguage: Locale.Language
    let targetLanguage: Locale.Language
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                configuration = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
            }
            .onChange(of: sourceLanguage.minimalIdentifier) { _, _ in
                configuration = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
            }
            .onChange(of: targetLanguage.minimalIdentifier) { _, _ in
                configuration = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
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
    }
}
