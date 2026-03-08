//
//  WordNetEntry.swift
//  SnapTra Translator
//
//  Data model for WordNet dictionary entries.
//  WordNet is a lexical database of English with synsets (synonym sets).
//

import Foundation

/// A dictionary entry from WordNet, containing synsets (groups of synonymous words).
struct WordNetEntry {
    /// The word that was looked up.
    let word: String

    /// All synsets (meanings) for this word, ordered by most common sense first.
    let synsets: [Synset]

    /// A single meaning of a word, containing the definition, examples, and synonyms.
    struct Synset: Equatable {
        /// Unique WordNet identifier, e.g., "02084071-n"
        let id: String

        /// Part of speech (noun, verb, adjective, adverb).
        let pos: PartOfSpeech

        /// The definition of this meaning.
        let definition: String

        /// Example sentences showing usage.
        let examples: [String]

        /// All words that share this meaning (synonyms).
        let lemmas: [String]
    }

    /// Part of speech categories in WordNet.
    enum PartOfSpeech: String, Codable, Equatable {
        case noun = "n"
        case verb = "v"
        case adjective = "a"
        case adverb = "r"
        case adjectiveSatellite = "s"  // Adjective satellite (related adjectives)

        /// Human-readable display name for UI.
        var displayName: String {
            switch self {
            case .noun: return "n."
            case .verb: return "v."
            case .adjective, .adjectiveSatellite: return "adj."
            case .adverb: return "adv."
            }
        }

        /// Full name for accessibility and detailed display.
        var fullName: String {
            switch self {
            case .noun: return "noun"
            case .verb: return "verb"
            case .adjective: return "adjective"
            case .adverb: return "adverb"
            case .adjectiveSatellite: return "adjective"
            }
        }

        /// Initialize from WordNet's single-character POS code.
        init?(fromRaw raw: String) {
            switch raw.lowercased() {
            case "n": self = .noun
            case "v": self = .verb
            case "a": self = .adjective
            case "r": self = .adverb
            case "s": self = .adjectiveSatellite
            default: return nil
            }
        }
    }

    // MARK: - Computed Properties

    /// All unique synonyms across all synsets, excluding the original word.
    var allSynonyms: [String] {
        var allLemmas = Set<String>()
        for synset in synsets {
            allLemmas.formUnion(synset.lemmas)
        }
        allLemmas.remove(word.lowercased())
        return Array(allLemmas).sorted()
    }

    /// The primary (most common) definition.
    var primaryDefinition: String? {
        synsets.first?.definition
    }

    /// All examples from all synsets, limited to avoid overwhelming the UI.
    var allExamples: [String] {
        synsets.flatMap { $0.examples }.prefix(3).map { $0 }
    }

    /// Whether this entry has any data.
    var isEmpty: Bool {
        synsets.isEmpty
    }
}

// MARK: - Conversion to DictionaryEntry

extension WordNetEntry {
    /// Convert to a generic DictionaryEntry for display.
    /// - Parameters:
    ///   - translatedMeanings: Optional pre-translated meanings (from Translation API).
    /// - Returns: A DictionaryEntry suitable for the app's dictionary display.
    func toDictionaryEntry(translatedMeanings: [DictionaryEntry.Definition]? = nil) -> DictionaryEntry {
        let definitions: [DictionaryEntry.Definition]

        if let translated = translatedMeanings, !translated.isEmpty {
            definitions = translated
        } else {
            // Convert synsets to definitions
            definitions = synsets.prefix(3).map { synset in
                DictionaryEntry.Definition(
                    partOfSpeech: synset.pos.displayName,
                    field: nil,  // WordNet doesn't have field markers
                    meaning: synset.definition,
                    translation: nil,  // WordNet is English-only
                    examples: Array(synset.examples.prefix(2))
                )
            }
        }

        return DictionaryEntry(
            word: word,
            phonetic: nil,  // WordNet doesn't include phonetics
            definitions: definitions,
            source: .wordNet,
            synonyms: allSynonyms
        )
    }
}