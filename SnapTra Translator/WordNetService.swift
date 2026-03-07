//
//  WordNetService.swift
//  SnapTra Translator
//
//  SQLite-based lookup service for WordNet dictionary.
//  WordNet is a lexical database of English with synsets (synonym sets).
//

import Foundation
import SQLite3

/// Queries a WordNet SQLite database for English word definitions, examples, and synonyms.
/// Database location: ~/Library/Application Support/SnapTra Translator/Dictionaries/wordnet.db
final class WordNetService {

    static let databaseFilename = "wordnet.db"

    static var databaseDirectory: URL {
        OfflineDictionaryService.databaseDirectory
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

    // MARK: - Public API

    /// Look up a word in the WordNet database.
    /// - Parameter word: The word to look up (case-insensitive).
    /// - Returns: A WordNetEntry if found, or nil.
    func lookup(_ word: String) -> WordNetEntry? {
        guard db != nil else { return nil }

        // Try exact match first, then lowercase variant
        let lowercased = word.lowercased()
        for variant in [word, lowercased] {
            if let entry = queryWord(variant) {
                return entry
            }
        }

        // Try inflection variants (running → run, played → play, etc.)
        for variant in wordInflections(lowercased) {
            if let entry = queryWord(variant) {
                return entry
            }
        }

        return nil
    }

    /// Get all synonyms for a word across all synsets.
    /// - Parameter word: The word to find synonyms for.
    /// - Returns: Array of unique synonym strings, excluding the original word.
    func synonyms(for word: String) -> [String] {
        guard let entry = lookup(word) else { return [] }
        return entry.allSynonyms
    }

    // MARK: - Private

    private func openDatabase() {
        let path = Self.databaseURL.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            print("[WordNetService] Failed to open database: \(path)")
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

    /// Query the database for a specific word form.
    private func queryWord(_ word: String) -> WordNetEntry? {
        guard let dbHandle = db else { return nil }

        // Query synsets for this word
        let sql = """
            SELECT DISTINCT s.synset_id, s.pos, s.definition, s.examples
            FROM synsets s
            JOIN words w ON s.synset_id = w.synset_id
            WHERE w.lemma = ? COLLATE NOCASE
            ORDER BY s.synset_id
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(dbHandle, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmtHandle = stmt else { return nil }
        defer { sqlite3_finalize(stmtHandle) }

        sqlite3_bind_text(stmtHandle, 1, (word as NSString).utf8String, -1, nil)

        var synsets: [WordNetEntry.Synset] = []
        while sqlite3_step(stmtHandle) == SQLITE_ROW {
            guard let synset = parseSynset(stmtHandle, db: dbHandle) else { continue }
            synsets.append(synset)
        }

        guard !synsets.isEmpty else { return nil }
        return WordNetEntry(word: word, synsets: synsets)
    }

    /// Parse a synset from a database row.
    private func parseSynset(_ stmt: OpaquePointer, db: OpaquePointer) -> WordNetEntry.Synset? {
        guard let id = columnString(stmt, 0),
              let posRaw = columnString(stmt, 1),
              let pos = WordNetEntry.PartOfSpeech(fromRaw: posRaw),
              let definition = columnString(stmt, 2) else {
            return nil
        }

        // Parse examples (pipe-separated or stored as JSON array)
        let examplesRaw = columnString(stmt, 3) ?? ""
        let examples = parseExamples(examplesRaw)

        // Query lemmas (synonyms) for this synset
        let lemmas = queryLemmas(for: id, db: db)

        return WordNetEntry.Synset(
            id: id,
            pos: pos,
            definition: definition,
            examples: examples,
            lemmas: lemmas
        )
    }

    /// Parse examples from stored format.
    private func parseExamples(_ raw: String) -> [String] {
        // Handle pipe-separated format: "example1|example2|example3"
        // or JSON array format: ["example1", "example2"]
        if raw.hasPrefix("[") {
            // JSON array - try to parse
            let stripped = raw
                .replacingOccurrences(of: "[\"", with: "")
                .replacingOccurrences(of: "\"]", with: "")
                .replacingOccurrences(of: "\",\"", with: "|")
            return stripped.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            // Pipe-separated or single example
            return raw.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    /// Query all lemmas (synonyms) for a synset.
    private func queryLemmas(for synsetId: String, db: OpaquePointer) -> [String] {
        let sql = "SELECT lemma FROM words WHERE synset_id = ? ORDER BY lemma"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (synsetId as NSString).utf8String, -1, nil)

        var lemmas: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let lemma = columnString(stmt, 0) {
                lemmas.append(lemma)
            }
        }
        return lemmas
    }

    /// Generate inflection variants for a word (lemmatization).
    private func wordInflections(_ word: String) -> [String] {
        var variants: [String] = []

        // Present participle: running → run, making → make
        if word.hasSuffix("ing"), word.count > 5 {
            let base = String(word.dropLast(3))
            variants.append(base)
            variants.append(base + "e")
        }

        // Past tense: played → play, loved → love
        if word.hasSuffix("ed"), word.count > 4 {
            let base = String(word.dropLast(2))
            variants.append(base)
            variants.append(base + "e")
        }

        // Comparative/superlative: faster → fast, fastest → fast
        if word.hasSuffix("er"), word.count > 4 {
            variants.append(String(word.dropLast(2)))
            if word.hasSuffix("ier") {
                variants.append(String(word.dropLast(3)) + "y")
            }
        }
        if word.hasSuffix("est"), word.count > 5 {
            variants.append(String(word.dropLast(3)))
            if word.hasSuffix("iest") {
                variants.append(String(word.dropLast(4)) + "y")
            }
        }

        // Plural: libraries → library, cats → cat
        if word.hasSuffix("ies"), word.count > 5 {
            variants.append(String(word.dropLast(3)) + "y")
        } else if word.hasSuffix("es"), word.count > 4 {
            variants.append(String(word.dropLast(2)))
            variants.append(String(word.dropLast(1)))
        } else if word.hasSuffix("s"), word.count > 3 {
            variants.append(String(word.dropLast(1)))
        }

        // Adverb: quickly → quick
        if word.hasSuffix("ly"), word.count > 5 {
            let base = String(word.dropLast(2))
            variants.append(base)
            if base.hasSuffix("i") {
                variants.append(String(base.dropLast(1)) + "y")
            }
        }

        return variants
    }

    private func columnString(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, col) else { return nil }
        let str = String(cString: cStr)
        return str.isEmpty ? nil : str
    }

    // MARK: - Validation

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

        // Check for expected tables
        let sql = "SELECT 1 FROM synsets LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return "Missing 'synsets' table"
        }

        let stepResult = sqlite3_step(stmt)
        guard stepResult == SQLITE_ROW || stepResult == SQLITE_DONE else {
            return String(cString: sqlite3_errmsg(db))
        }

        sqlite3_finalize(stmt)
        stmt = nil

        // Check for words table
        let sql2 = "SELECT 1 FROM words LIMIT 1"
        guard sqlite3_prepare_v2(db, sql2, -1, &stmt, nil) == SQLITE_OK else {
            return "Missing 'words' table"
        }

        return nil
    }
}