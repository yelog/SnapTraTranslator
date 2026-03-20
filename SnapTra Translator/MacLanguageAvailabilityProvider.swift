import Combine
import Foundation
import Translation

@MainActor
final class MacLanguageAvailabilityProvider: LanguageAvailabilityProviding {
    var isChecking: Bool {
        publishedIsChecking
    }

    var isCheckingPublisher: AnyPublisher<Bool, Never> {
        $publishedIsChecking.eraseToAnyPublisher()
    }

    var statusesPublisher: AnyPublisher<[String: LanguageAvailabilityStatus], Never> {
        $publishedStatuses.eraseToAnyPublisher()
    }

    @Published private var publishedStatuses: [String: LanguageAvailabilityStatus] = [:]
    @Published private var publishedIsChecking = false

    private var storage: Any?
    private var cancellables = Set<AnyCancellable>()

    init() {
        if #available(macOS 15.0, *) {
            let manager = LanguagePackManager()
            storage = manager
            publishedIsChecking = manager.isChecking
            publishedStatuses = manager.languageStatuses.mapValues(LanguageAvailabilityStatus.init)

            manager.$languageStatuses
                .map { statuses in
                    statuses.mapValues(LanguageAvailabilityStatus.init)
                }
                .sink { [weak self] statuses in
                    self?.publishedStatuses = statuses
                }
                .store(in: &cancellables)

            manager.$isChecking
                .sink { [weak self] isChecking in
                    self?.publishedIsChecking = isChecking
                }
                .store(in: &cancellables)
        }
    }

    func checkLanguagePair(from sourceLanguage: String, to targetLanguage: String) async -> LanguageAvailabilityStatus {
        guard #available(macOS 15.0, *), let manager = storage as? LanguagePackManager else {
            return .unsupported
        }
        return .init(await manager.checkLanguagePair(from: sourceLanguage, to: targetLanguage))
    }

    func checkLanguagePairQuiet(from sourceLanguage: String, to targetLanguage: String) async -> LanguageAvailabilityStatus {
        guard #available(macOS 15.0, *), let manager = storage as? LanguagePackManager else {
            return .unsupported
        }
        return .init(await manager.checkLanguagePairQuiet(from: sourceLanguage, to: targetLanguage))
    }

    func getStatus(from sourceLanguage: String, to targetLanguage: String) -> LanguageAvailabilityStatus? {
        guard #available(macOS 15.0, *), let manager = storage as? LanguagePackManager else {
            return nil
        }
        guard let status = manager.getStatus(from: sourceLanguage, to: targetLanguage) else {
            return nil
        }
        return .init(status)
    }

    func openTranslationSettings() {
        if #available(macOS 15.0, *), let manager = storage as? LanguagePackManager {
            manager.openTranslationSettings()
        }
    }
}

private extension LanguageAvailabilityStatus {
    @available(macOS 15.0, *)
    init(_ status: LanguageAvailability.Status) {
        switch status {
        case .installed:
            self = .installed
        case .supported:
            self = .supported
        case .unsupported:
            self = .unsupported
        @unknown default:
            self = .unknown
        }
    }
}
