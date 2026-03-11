//
//  FreeDictionaryService.swift
//  SnapTra Translator
//
//  Free Dictionary API (dictionaryapi.dev) integration.
//

import Foundation
import os.log

/// Free Dictionary API service - provides English word definitions, phonetics, and examples.
/// Documentation: https://dictionaryapi.dev/
final class FreeDictionaryService {
    private let session: URLSession
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "FreeDictionary")

    init(session: URLSession = FreeDictionaryService.makeSession()) {
        self.session = session
    }

    /// Looks up an English word in the Free Dictionary API.
    /// - Parameter word: The English word to look up
    /// - Returns: DictionaryEntry if found, nil otherwise
    func lookup(_ word: String) async -> DictionaryEntry? {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return nil }

        // Free Dictionary API only supports English
        let normalizedWord = trimmedWord.lowercased()

        guard let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(normalizedWord.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedWord)") else {
            logger.error("Failed to construct URL for word: \(normalizedWord, privacy: .public)")
            return nil
        }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
                    logger.debug("Word not found: \(normalizedWord, privacy: .public)")
                } else {
                    logger.error("HTTP error for \(normalizedWord, privacy: .public)")
                }
                return nil
            }

            let entries = try JSONDecoder().decode([FreeDictionaryEntry].self, from: data)
            return convertToDictionaryEntry(entries, originalWord: word)

        } catch {
            logger.error("Lookup failed for \(normalizedWord, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Private

    private func convertToDictionaryEntry(_ entries: [FreeDictionaryEntry], originalWord: String) -> DictionaryEntry? {
        guard let firstEntry = entries.first else { return nil }

        // Extract phonetic - prefer audio-linked phonetic, fallback to any available
        let phonetic = extractBestPhonetic(from: firstEntry)

        // Convert meanings to definitions
        var definitions: [DictionaryEntry.Definition] = []

        for meaning in firstEntry.meanings {
            let pos = normalizePartOfSpeech(meaning.partOfSpeech)

            for def in meaning.definitions {
                // Use example from definition if available
                var examples: [String] = []
                if let example = def.example, !example.isEmpty {
                    examples.append(example)
                }

                // Add synonyms as part of meaning if available
                var meaningText = def.definition
                if !def.synonyms.isEmpty {
                    let synonymText = def.synonyms.prefix(5).joined(separator: ", ")
                    meaningText += " (syn: \(synonymText))"
                }

                definitions.append(DictionaryEntry.Definition(
                    partOfSpeech: pos,
                    field: nil,
                    meaning: meaningText,
                    translation: nil, // Free Dictionary is English-only
                    examples: examples
                ))
            }
        }

        // Collect synonyms from all meanings
        var allSynonyms: [String] = []
        for meaning in firstEntry.meanings {
            for def in meaning.definitions {
                allSynonyms.append(contentsOf: def.synonyms)
            }
        }
        let uniqueSynonyms: [String] = Array(Set(allSynonyms).prefix(10))

        guard !definitions.isEmpty else { return nil }

        return DictionaryEntry(
            word: originalWord,
            phonetic: phonetic,
            definitions: definitions,
            source: .freeDictionary,
            synonyms: uniqueSynonyms,
            isPretranslated: false
        )
    }

    private func extractBestPhonetic(from entry: FreeDictionaryEntry) -> String? {
        // Prefer phonetic with audio (US accent preferred)
        var usPhonetic: String?
        var ukPhonetic: String?
        var anyPhonetic: String?

        for phonetic in entry.phonetics {
            let text = phonetic.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text, !text.isEmpty else { continue }

            anyPhonetic = anyPhonetic ?? text

            if let audio = phonetic.audio, !audio.isEmpty {
                if audio.contains("-us.") || audio.contains("/us/") {
                    usPhonetic = text
                } else if audio.contains("-uk.") || audio.contains("/uk/") {
                    ukPhonetic = text
                }
            }
        }

        // Build combined phonetic if we have both US and UK
        if let us = usPhonetic, let uk = ukPhonetic, us != uk {
            return "US \(us)  UK \(uk)"
        }

        return usPhonetic ?? ukPhonetic ?? anyPhonetic ?? entry.phonetic
    }

    private func normalizePartOfSpeech(_ pos: String) -> String {
        let lowercased = pos.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch lowercased {
        case "noun": return "n."
        case "verb": return "v."
        case "adjective": return "adj."
        case "adverb": return "adv."
        case "preposition": return "prep."
        case "conjunction": return "conj."
        case "pronoun": return "pron."
        case "interjection": return "interj."
        case "determiner": return "det."
        case "modal verb": return "modal v."
        case "phrasal verb": return "phr. v."
        default: return lowercased
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }
}

// MARK: - Data Models

private struct FreeDictionaryEntry: Decodable {
    let word: String
    let phonetic: String?
    let phonetics: [Phonetic]
    let meanings: [Meaning]

    struct Phonetic: Decodable {
        let text: String?
        let audio: String?
        let sourceUrl: String?
        let license: License?
    }

    struct Meaning: Decodable {
        let partOfSpeech: String
        let definitions: [Definition]
        let synonyms: [String]
        let antonyms: [String]
    }

    struct Definition: Decodable {
        let definition: String
        let synonyms: [String]
        let antonyms: [String]
        let example: String?
    }

    struct License: Decodable {
        let name: String
        let url: String
    }
}
