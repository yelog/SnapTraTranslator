import Foundation

/// Queries an offline ECDICT SQLite database for English word definitions.
/// Database location: ~/Library/Application Support/SnapTra Translator/Dictionaries/stardict.db
final class OfflineDictionaryService {
    static let databaseFilename = OfflineDictionaryStore.databaseFilename

    static var databaseDirectory: URL {
        OfflineDictionaryStore.databaseDirectory
    }

    static var databaseURL: URL {
        OfflineDictionaryStore.databaseURL
    }

    var isDatabaseInstalled: Bool {
        store.isDatabaseInstalled
    }

    var databaseValidationError: String? {
        store.databaseValidationError
    }

    private let store: OfflineDictionaryStore

    init(store: OfflineDictionaryStore = OfflineDictionaryStore()) {
        self.store = store
    }

    /// Reloads the database connection. Call after installing or deleting the database file.
    func reload() {
        store.reload()
    }

    func lookup(_ word: String) -> DictionaryEntry? {
        store.lookup(word)
    }

    static func validationError(at url: URL) -> String? {
        OfflineDictionaryStore.validationError(at: url)
    }
}
