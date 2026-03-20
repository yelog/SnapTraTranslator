import Foundation

final class DictionaryService {
    /// Offline ECDICT database. Exposed so AppModel can pass it to DictionaryDownloadManager.
    let offlineService = OfflineDictionaryService()
    private let systemProvider = MacSystemDictionaryProvider()

    /// Performs a lookup using the provided dictionary sources in priority order.
    /// - Parameters:
    ///   - word: The word to look up
    ///   - sources: Array of dictionary sources to query (in priority order)
    ///   - preferEnglish: Whether to prefer English definitions
    /// - Returns: The first matching dictionary entry, or nil if not found
    func lookup(_ word: String, sources: [DictionarySource], preferEnglish: Bool = false) -> DictionaryEntry? {
        guard let normalized = normalizeWord(word) else { return nil }

        // Query each enabled source in order
        for source in sources where source.isEnabled {
            if let entry = Self.lookupFromLocalSource(
                source,
                word: normalized,
                preferEnglish: preferEnglish,
                offlineService: offlineService,
                systemProvider: systemProvider
            ) {
                return entry
            }
        }

        return nil
    }

    /// Queries a single dictionary source and returns the matching entry.
    /// - Parameters:
    ///   - word: The word to look up
    ///   - source: Dictionary source to query
    ///   - sourceLanguage: Source language code (unused, kept for API compatibility)
    ///   - targetLanguage: Target language code (unused, kept for API compatibility)
    ///   - preferEnglish: Whether to prefer English definitions
    /// - Returns: Dictionary entry, or nil if not found
    func lookupSingle(
        _ word: String,
        source: DictionarySource,
        sourceLanguage: String,
        targetLanguage: String,
        preferEnglish: Bool = false
    ) async -> DictionaryEntry? {
        guard source.isEnabled, let normalized = normalizeWord(word) else { return nil }

        return Self.lookupFromLocalSource(
            source,
            word: normalized,
            preferEnglish: preferEnglish,
            offlineService: offlineService,
            systemProvider: systemProvider
        )
    }

    func lookupAll(
        _ word: String,
        sources: [DictionarySource],
        sourceLanguage: String,
        targetLanguage: String,
        preferEnglish: Bool = false
    ) async -> [DictionaryEntry] {
        guard let normalized = normalizeWord(word) else { return [] }

        var entries: [DictionaryEntry] = []
        for source in sources where source.isEnabled {
            if let entry = await lookupSingle(
                normalized,
                source: source,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                preferEnglish: preferEnglish
            ) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// Legacy lookup method for backward compatibility - tries ECDICT first, then system.
    func lookup(_ word: String, preferEnglish: Bool = false) -> DictionaryEntry? {
        guard let normalized = normalizeWord(word) else { return nil }

        // Prefer offline dictionary for better coverage
        if let entry = offlineService.lookup(normalized) {
            return entry
        }

        return systemProvider.lookup(word: normalized, preferEnglish: preferEnglish)
    }

    // MARK: - Private

    private static func lookupFromLocalSource(
        _ source: DictionarySource,
        word: String,
        preferEnglish: Bool,
        offlineService: OfflineDictionaryService,
        systemProvider: MacSystemDictionaryProvider
    ) -> DictionaryEntry? {
        switch source.type {
        case .ecdict:
            guard let entry = offlineService.lookup(word) else { return nil }
            return DictionaryEntry(
                word: entry.word,
                phonetic: entry.phonetic,
                definitions: entry.definitions,
                source: .advancedDictionary,
                synonyms: entry.synonyms
            )
        case .system:
            return systemProvider.lookup(word: word, preferEnglish: preferEnglish)
        }
    }

    // MARK: - Private

    private func normalizeWord(_ word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let firstToken = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? trimmed
        let allowed = CharacterSet.letters.union(CharacterSet(charactersIn: "-''"))
        let cleaned = firstToken.trimmingCharacters(in: allowed.inverted)
        return cleaned.isEmpty ? nil : cleaned.lowercased()
    }
}

extension DictionaryService: DictionaryProviding {}
