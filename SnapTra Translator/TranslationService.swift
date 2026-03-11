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
    @Published private(set) var activeRequest: TranslationRequest?
    private var queuedRequests: [TranslationRequest] = []

    func translate(text: String, source: Locale.Language?, target: Locale.Language, timeout: TimeInterval = 10.0) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyText
        }
        try Task.checkCancellation()

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    let request = TranslationRequest(id: UUID(), text: trimmed, source: source, target: target, continuation: continuation)
                    Task { @MainActor in
                        self.enqueue(request)
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

    func finishActiveRequest(id: UUID, result: Result<String, Error>) {
        guard activeRequest?.id == id else { return }

        switch result {
        case .success(let translatedText):
            activeRequest?.continuation.resume(returning: translatedText)
        case .failure(let error):
            activeRequest?.continuation.resume(throwing: error)
        }

        activeRequest = nil
        promoteNextRequestIfNeeded()
    }

    func cancelAllPendingRequests(with error: Error = CancellationError()) {
        if let activeRequest {
            activeRequest.continuation.resume(throwing: error)
            self.activeRequest = nil
        }

        for request in queuedRequests {
            request.continuation.resume(throwing: error)
        }
        queuedRequests.removeAll()
    }

    private func enqueue(_ request: TranslationRequest) {
        queuedRequests.append(request)
        promoteNextRequestIfNeeded()
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
            .translationTask(configuration) { session in
                guard let request = bridge.activeRequest else {
                    return
                }

                do {
                    let response = try await session.translate(request.text)
                    bridge.finishActiveRequest(id: request.id, result: .success(response.targetText))
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
        configuration = TranslationSession.Configuration(
            source: request.source,
            target: request.target
        )
    }
}
