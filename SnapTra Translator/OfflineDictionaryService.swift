import Foundation
import SQLite3

/// Queries an offline ECDICT SQLite database for English word definitions.
/// Database location: ~/Library/Application Support/SnapTra Translator/Dictionaries/stardict.db
final class OfflineDictionaryService {

    static let databaseFilename = "stardict.db"

    static var databaseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SnapTra Translator/Dictionaries")
    }

    static var databaseURL: URL {
        databaseDirectory.appendingPathComponent(databaseFilename)
    }

    var isDatabaseInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.databaseURL.path)
    }

    var databaseValidationError: String? {
        Self.validationError(at: Self.databaseURL)
    }

    private var db: OpaquePointer?

    init() {
        openDatabase()
    }

    deinit {
        closeDatabase()
    }

    /// Reloads the database connection. Call after installing or deleting the database file.
    func reload() {
        closeDatabase()
        openDatabase()
    }

    func lookup(_ word: String) -> DictionaryEntry? {
        guard db != nil else { return nil }
        for variant in wordVariants(word) {
            if let entry = queryDatabase(variant) { return entry }
        }
        return nil
    }

    // MARK: - Private

    private func openDatabase() {
        let path = Self.databaseURL.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            db = nil
            return
        }
    }

    private func closeDatabase() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    /// Returns lookup candidates: exact form first, then common inflection stems.
    private func wordVariants(_ word: String) -> [String] {
        let lower = word.lowercased()
        var variants = [lower]

        // Present participle: running → run, making → make
        if lower.hasSuffix("ing"), lower.count > 5 {
            let base = String(lower.dropLast(3))
            variants.append(base)
            variants.append(base + "e")
        }
        // Past tense: played → play, loved → love
        if lower.hasSuffix("ed"), lower.count > 4 {
            let base = String(lower.dropLast(2))
            variants.append(base)
            variants.append(base + "e")
        }
        // Plural: libraries → library, cats → cat
        if lower.hasSuffix("ies"), lower.count > 5 {
            variants.append(String(lower.dropLast(3)) + "y")
        } else if lower.hasSuffix("s"), lower.count > 3 {
            variants.append(String(lower.dropLast(1)))
        }
        return variants
    }

    private func queryDatabase(_ word: String) -> DictionaryEntry? {
        guard let db else { return nil }
        let sql = "SELECT word, phonetic, definition, translation FROM stardict WHERE word = ? COLLATE NOCASE LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let foundWord   = columnString(stmt, 0) ?? word
        let phonetic    = columnString(stmt, 1)
        let definition  = columnString(stmt, 2)
        let translation = columnString(stmt, 3)

        let defs = buildDefinitions(translation: translation, definition: definition)
        guard !defs.isEmpty else { return nil }
        return DictionaryEntry(word: foundWord, phonetic: phonetic, definitions: defs)
    }

    /// Parses ECDICT fields into a Definition array.
    ///
    /// translation format: "n. 苹果；苹果公司\nvt. 捏"
    /// definition format:  "n. A common round fruit produced by the tree..."
    private func buildDefinitions(translation: String?, definition: String?) -> [DictionaryEntry.Definition] {
        var result: [DictionaryEntry.Definition] = []

        if let translation, !translation.isEmpty {
            for line in translation.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let (pos, meaning) = extractPOSAndMeaning(trimmed)
                guard !meaning.isEmpty else { continue }
                result.append(DictionaryEntry.Definition(
                    partOfSpeech: pos,
                    meaning: meaning,
                    translation: meaning,
                    examples: []
                ))
            }
        }

        // Fall back to English definition if no Chinese translation is available
        if result.isEmpty, let definition, !definition.isEmpty {
            for line in definition.components(separatedBy: "\n").prefix(3) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let (pos, meaning) = extractPOSAndMeaning(trimmed)
                guard !meaning.isEmpty else { continue }
                result.append(DictionaryEntry.Definition(
                    partOfSpeech: pos,
                    meaning: meaning,
                    translation: nil,
                    examples: []
                ))
            }
        }
        return result
    }

    /// Splits "n. 苹果" → ("n.", "苹果"). Returns ("", original) if no POS prefix found.
    private func extractPOSAndMeaning(_ line: String) -> (String, String) {
        let pattern = #"^(n\.|vt\.|vi\.|v\.|adj\.|adv\.|prep\.|conj\.|pron\.|interj\.|num\.|art\.|abbr\.)\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let posRange = Range(match.range(at: 1), in: line),
              let fullRange = Range(match.range, in: line) else {
            return ("", line)
        }
        let pos = String(line[posRange])
        let meaning = String(line[fullRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (pos, meaning)
    }

    private func columnString(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, col) else { return nil }
        let str = String(cString: cStr)
        return str.isEmpty ? nil : str
    }

    static func validationError(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let db {
                sqlite3_close(db)
            }
            return message
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql = "SELECT 1 FROM stardict LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return String(cString: sqlite3_errmsg(db))
        }

        let stepResult = sqlite3_step(stmt)
        guard stepResult == SQLITE_ROW || stepResult == SQLITE_DONE else {
            return String(cString: sqlite3_errmsg(db))
        }
        return nil
    }
}
