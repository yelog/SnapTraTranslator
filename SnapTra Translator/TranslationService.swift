import Combine
import Foundation
import SwiftUI
import Translation

enum TranslationError: Error {
    case unsupportedSystem
    case emptyText
    case timeout
    case invalidResponse
}

struct TranslationRequest {
    let id: UUID
    let source: Locale.Language?
    let target: Locale.Language
    let strategy: AppleTranslationStrategy
    let payload: TranslationPayload
    fileprivate let continuation: CheckedContinuation<TranslationPayload, Error>

    @available(macOS 15.0, *)
    var configuration: TranslationSession.Configuration {
        if #available(macOS 26.4, *) {
            return .init(source: source, target: target, preferredStrategy: strategy.systemStrategy)
        }
        return .init(source: source, target: target)
    }
}

extension AppleTranslationStrategy {
    @available(macOS 26.4, *)
    var systemStrategy: TranslationSession.Strategy {
        switch self {
        case .fast: .lowLatency
        case .qualityPreferred: .highFidelity
        }
    }

    @available(macOS 15.0, *)
    func makeLanguageAvailability() -> LanguageAvailability {
        if #available(macOS 26.4, *) {
            return LanguageAvailability(preferredStrategy: systemStrategy)
        }
        return LanguageAvailability()
    }
}

enum TranslationPayload {
    case single(String)
    case batch([String])
}

@MainActor
final class TranslationBridge: ObservableObject {
    @Published private(set) var activeRequest: TranslationRequest?
    private(set) var queuedRequests: [TranslationRequest] = []

    func translate(
        text: String,
        source: Locale.Language?,
        target: Locale.Language,
        strategy: AppleTranslationStrategy = .fast,
        timeout: TimeInterval = 10.0
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyText }
        let response = try await submit(.single(trimmed), source: source, target: target, strategy: strategy, timeout: timeout)
        guard case .single(let translation) = response else { throw TranslationError.invalidResponse }
        return translation
    }

    func translateBatch(
        texts: [String],
        source: Locale.Language?,
        target: Locale.Language,
        strategy: AppleTranslationStrategy = .fast,
        timeout: TimeInterval = 10.0
    ) async throws -> [String] {
        let trimmedTexts = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmedTexts.isEmpty else { throw TranslationError.emptyText }
        let response = try await submit(.batch(trimmedTexts), source: source, target: target, strategy: strategy, timeout: timeout)
        guard case .batch(let translations) = response else { throw TranslationError.invalidResponse }
        return translations
    }

    private func submit(
        _ payload: TranslationPayload,
        source: Locale.Language?,
        target: Locale.Language,
        strategy: AppleTranslationStrategy,
        timeout: TimeInterval
    ) async throws -> TranslationPayload {
        let id = UUID()
        var timeoutTask: Task<Void, Never>?
        defer { timeoutTask?.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Check and register on the same actor so cancellation cannot miss a new request.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                queuedRequests.append(TranslationRequest(
                    id: id,
                    source: source,
                    target: target,
                    strategy: strategy,
                    payload: payload,
                    continuation: continuation
                ))
                promoteNextRequestIfNeeded()
                timeoutTask = Task {
                    do {
                        try await Task.sleep(for: .seconds(timeout))
                    } catch {
                        return
                    }
                    cancelRequest(id: id, with: TranslationError.timeout)
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.cancelRequest(id: id, with: CancellationError())
            }
        }
    }

    func finishActiveRequest(id: UUID, result: Result<TranslationPayload, Error>) {
        guard let request = activeRequest, request.id == id else { return }
        activeRequest = nil
        request.continuation.resume(with: result)
        promoteNextRequestIfNeeded()
    }

    private func cancelRequest(id: UUID, with error: Error) {
        if activeRequest?.id == id {
            finishActiveRequest(id: id, result: .failure(error))
        } else if let index = queuedRequests.firstIndex(where: { $0.id == id }) {
            queuedRequests.remove(at: index).continuation.resume(throwing: error)
        }
    }

    func cancelAllPendingRequests(with error: Error = CancellationError()) {
        activeRequest?.continuation.resume(throwing: error)
        activeRequest = nil
        for request in queuedRequests {
            request.continuation.resume(throwing: error)
        }
        queuedRequests.removeAll()
    }

    private func promoteNextRequestIfNeeded() {
        guard activeRequest == nil, !queuedRequests.isEmpty else { return }
        activeRequest = queuedRequests.removeFirst()
    }
}

@available(macOS 15.0, *)
struct TranslationBridgeView: View {
    @ObservedObject var bridge: TranslationBridge
    @State private var configuration: TranslationSession.Configuration?
    @State private var configurationID = UUID()

    init(bridge: TranslationBridge) {
        self.bridge = bridge
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                syncConfiguration(for: bridge.activeRequest)
            }
            .onChange(of: bridge.activeRequest?.id) { _, _ in
                syncConfiguration(for: bridge.activeRequest)
            }
            .translationTask(configuration) { [configurationID] session in
                guard let request = bridge.activeRequest, request.id == configurationID else {
                    return
                }

                do {
                    switch request.payload {
                    case .single(let text):
                        let response = try await session.translate(text)
                        bridge.finishActiveRequest(id: request.id, result: .success(.single(response.targetText)))
                    case .batch(let texts):
                        let batch = texts.enumerated().map { index, text in
                            TranslationSession.Request(
                                sourceText: text,
                                clientIdentifier: String(index)
                            )
                        }
                        let responses = try await session.translations(from: batch)
                        let sortedResponses = responses.sorted { lhs, rhs in
                            let lhsIndex = Int(lhs.clientIdentifier ?? "") ?? Int.max
                            let rhsIndex = Int(rhs.clientIdentifier ?? "") ?? Int.max
                            return lhsIndex < rhsIndex
                        }
                        let translatedTexts = sortedResponses.map(\.targetText)

                        guard translatedTexts.count == texts.count else {
                            throw TranslationError.invalidResponse
                        }

                        bridge.finishActiveRequest(id: request.id, result: .success(.batch(translatedTexts)))
                    }
                } catch {
                    bridge.finishActiveRequest(id: request.id, result: .failure(error))
                }
            }
            .id(configurationID)
    }

    private func syncConfiguration(for request: TranslationRequest?) {
        guard let request else {
            configuration = nil
            return
        }

        configurationID = request.id
        configuration = request.configuration
    }
}
