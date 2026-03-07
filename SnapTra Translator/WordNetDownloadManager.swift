import AppKit
import Combine
import Foundation

/// Manages downloading, installing, and deleting the WordNet offline dictionary database.
@MainActor
final class WordNetDownloadManager: ObservableObject {

    enum State: Equatable {
        case notInstalled
        case downloading(progress: Double)
        case installing
        case installed(sizeMB: Double)
        case error(String)
    }

    @Published var state: State = .notInstalled

    // WordNet SQLite database URL.
    // TODO: Update this URL when hosting the actual WordNet database.
    // For now, using a placeholder. The actual database needs to be prepared and hosted.
    private static let downloadURL = URL(string:
        "https://github.com/wn/sqlite-wordnet/releases/download/v1.0/wordnet.db"
    )!

    private let wordNetService: WordNetService
    private var urlSessionTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    init(wordNetService: WordNetService) {
        self.wordNetService = wordNetService
        refreshState()
    }

    func refreshState() {
        if let validationError = wordNetService.databaseValidationError {
            state = .error("Installed dictionary is invalid: \(validationError)")
        } else if wordNetService.isDatabaseInstalled {
            state = .installed(sizeMB: installedFileSizeMB())
        } else {
            state = .notInstalled
        }
    }

    func startDownload() {
        guard case .notInstalled = state else { return }
        state = .downloading(progress: 0)

        let task = URLSession.shared.downloadTask(with: Self.downloadURL) { [weak self] tempURL, _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.state = .error(error.localizedDescription)
                    return
                }
                guard let tempURL else {
                    self.state = .error("Download failed")
                    return
                }
                self.state = .installing
                await self.install(from: tempURL)
            }
        }

        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                guard let self, case .downloading = self.state else { return }
                self.state = .downloading(progress: progress.fractionCompleted)
            }
        }

        urlSessionTask = task
        task.resume()
    }

    func cancelDownload() {
        urlSessionTask?.cancel()
        urlSessionTask = nil
        progressObservation = nil
        state = .notInstalled
    }

    func retry() {
        state = .notInstalled
        startDownload()
    }

    func delete() {
        try? FileManager.default.removeItem(at: WordNetService.databaseURL)
        wordNetService.reload()
        state = .notInstalled
    }

    // MARK: - Private

    private func install(from downloadedURL: URL) async {
        do {
            let dir = WordNetService.databaseDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let destURL = WordNetService.databaseURL
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }

            // WordNet database is a single .db file, no extraction needed
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.copyItem(at: downloadedURL, to: destURL)
            }.value

            try finalizeInstall()
        } catch {
            state = .error("Installation failed: \(error.localizedDescription)")
        }
    }

    private func installedFileSizeMB() -> Double {
        guard let attrs = try? FileManager.default.attributesOfItem(
            atPath: WordNetService.databaseURL.path
        ) else { return 0 }
        let bytes = (attrs[.size] as? Int64) ?? 0
        return Double(bytes) / 1_048_576
    }

    private func finalizeInstall() throws {
        wordNetService.reload()
        guard wordNetService.isDatabaseInstalled else {
            throw NSError(
                domain: "WordNetDownloadManager",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Database file not found after installation",
                ]
            )
        }
        if let validationError = wordNetService.databaseValidationError {
            try? FileManager.default.removeItem(at: WordNetService.databaseURL)
            wordNetService.reload()
            throw NSError(
                domain: "WordNetDownloadManager",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Installed dictionary is invalid: \(validationError)",
                ]
            )
        }
        state = .installed(sizeMB: installedFileSizeMB())
    }
}