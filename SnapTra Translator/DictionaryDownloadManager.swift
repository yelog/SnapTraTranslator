import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// Manages downloading, installing, and deleting the ECDICT offline dictionary database.
@MainActor
final class DictionaryDownloadManager: ObservableObject {

    enum State: Equatable {
        case notInstalled
        case downloading(progress: Double)
        case installing
        case installed(sizeMB: Double)
        case error(String)
    }

    @Published var state: State = .notInstalled

    // ECDICT SQLite release. Update URL at: https://github.com/skywind3000/ECDICT/releases
    private static let downloadURL = URL(string:
        "https://github.com/skywind3000/ECDICT/releases/download/1.0.28/ecdict-sqlite-28.zip"
    )!

    private let offlineService: OfflineDictionaryService
    private var urlSessionTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    init(offlineService: OfflineDictionaryService) {
        self.offlineService = offlineService
        refreshState()
    }

    func refreshState() {
        if let validationError = offlineService.databaseValidationError {
            state = .error("Installed dictionary is invalid: \(validationError)")
        } else if offlineService.isDatabaseInstalled {
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
        try? FileManager.default.removeItem(at: OfflineDictionaryService.databaseURL)
        offlineService.reload()
        state = .notInstalled
    }

    /// Opens NSOpenPanel so the user can manually select a stardict.db file.
    /// Use this as a fallback when automatic zip extraction is not available (e.g., sandboxed builds).
    func selectManually() {
        let panel = NSOpenPanel()
        panel.title = "Select Dictionary Database"
        panel.message = "Select the stardict.db file extracted from the ECDICT download."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.init(filenameExtension: "db") ?? .data]
        } else {
            panel.allowedFileTypes = ["db"]
        }
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        Task { await copyManualFile(from: sourceURL) }
    }

    // MARK: - Private

    private func install(from zipURL: URL) async {
        do {
            let dir = OfflineDictionaryService.databaseDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try await extractZip(zipURL, to: dir)
            try finalizeInstall()
        } catch {
            state = .error("Extraction failed: \(error.localizedDescription). You can also extract the zip manually and use \"Select file\" to locate stardict.db.")
        }
    }

    private func copyManualFile(from sourceURL: URL) async {
        do {
            let accessedSecurityScope = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessedSecurityScope {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let dir = OfflineDictionaryService.databaseDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = OfflineDictionaryService.databaseURL
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            try finalizeInstall()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Extracts the first .db file from a zip archive using pure Swift.
    /// Works in the App Sandbox — no external processes required.
    private func extractZip(_ zipURL: URL, to directory: URL) async throws {
        let destURL = directory.appendingPathComponent(OfflineDictionaryService.databaseFilename)
        // Read zip data on the current actor while we still hold the temp-file security scope.
        let zipData = try Data(contentsOf: zipURL)
        try await Task.detached(priority: .userInitiated) {
            let dbData = try ZipExtractor.extractFile(endingWith: ".db", from: zipData)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try dbData.write(to: destURL, options: .atomic)
        }.value
    }

    private func installedFileSizeMB() -> Double {
        guard let attrs = try? FileManager.default.attributesOfItem(
            atPath: OfflineDictionaryService.databaseURL.path
        ) else { return 0 }
        let bytes = (attrs[.size] as? Int64) ?? 0
        return Double(bytes) / 1_048_576
    }

    private func finalizeInstall() throws {
        offlineService.reload()
        guard offlineService.isDatabaseInstalled else {
            throw NSError(
                domain: "DictionaryDownloadManager",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Database file not found in downloaded archive",
                ]
            )
        }
        if let validationError = offlineService.databaseValidationError {
            try? FileManager.default.removeItem(at: OfflineDictionaryService.databaseURL)
            offlineService.reload()
            throw NSError(
                domain: "DictionaryDownloadManager",
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
