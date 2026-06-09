import Foundation

enum LearningExportFormat: CaseIterable {
    case plainText
    case ankiTSV
    case csv

    var displayName: String {
        switch self {
        case .plainText:
            return "TXT"
        case .ankiTSV:
            return "Anki TSV"
        case .csv:
            return "CSV"
        }
    }

    var fileExtension: String {
        switch self {
        case .plainText:
            return "txt"
        case .ankiTSV:
            return "tsv"
        case .csv:
            return "csv"
        }
    }
}

protocol LearningExportRecord {
    var exportWord: String { get }
    var exportSourceLanguageIdentifier: String? { get }
    var exportDefinitionText: String? { get }
    var exportLookupCount: Int { get }
    var exportReviewStage: Int { get }
    var exportIsMastered: Bool { get }
}

extension WordRecord: LearningExportRecord {
    var exportWord: String { word }
    var exportSourceLanguageIdentifier: String? { sourceLanguageIdentifier }
    var exportDefinitionText: String? { definitionText }
    var exportLookupCount: Int { lookupCount }
    var exportReviewStage: Int { reviewStage }
    var exportIsMastered: Bool { isMastered }
}

struct LearningExportRow: Equatable {
    var word: String
    var sourceLanguageName: String
    var definitionText: String
    var lookupCount: Int
    var reviewStage: Int
    var isMastered: Bool

    init(record: any LearningExportRecord) {
        self.word = record.exportWord
        self.sourceLanguageName = LearningLanguageDisplay.name(for: record.exportSourceLanguageIdentifier)
        self.definitionText = record.exportDefinitionText ?? ""
        self.lookupCount = record.exportLookupCount
        self.reviewStage = record.exportReviewStage
        self.isMastered = record.exportIsMastered
    }

    init(
        word: String,
        sourceLanguageName: String,
        definitionText: String,
        lookupCount: Int,
        reviewStage: Int,
        isMastered: Bool
    ) {
        self.word = word
        self.sourceLanguageName = sourceLanguageName
        self.definitionText = definitionText
        self.lookupCount = lookupCount
        self.reviewStage = reviewStage
        self.isMastered = isMastered
    }
}

enum LearningExportService {
    static func export(rows: [LearningExportRow], format: LearningExportFormat) -> String {
        switch format {
        case .plainText:
            return plainText(rows: rows)
        case .ankiTSV:
            return tabSeparated(rows: rows)
        case .csv:
            return commaSeparated(rows: rows)
        }
    }

    private static func plainText(rows: [LearningExportRow]) -> String {
        guard !rows.isEmpty else { return "" }
        return rows
            .map { escapePlainTextWord($0.word) }
            .joined(separator: "\n") + "\n"
    }

    private static func tabSeparated(rows: [LearningExportRow]) -> String {
        export(
            rows: rows,
            separator: "\t",
            escape: escapeTSVField
        )
    }

    private static func commaSeparated(rows: [LearningExportRow]) -> String {
        export(
            rows: rows,
            separator: ",",
            escape: escapeCSVField
        )
    }

    private static func export(
        rows: [LearningExportRow],
        separator: String,
        escape: (String) -> String
    ) -> String {
        let header = ["Word", "Language", "Definition", "Lookup Count", "Review Stage", "Mastered"]
        let lines = [header.map(escape).joined(separator: separator)] + rows.map { row in
            [
                row.word,
                row.sourceLanguageName,
                row.definitionText,
                String(row.lookupCount),
                String(row.reviewStage),
                row.isMastered ? "true" : "false",
            ]
            .map(escape)
            .joined(separator: separator)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func escapePlainTextWord(_ word: String) -> String {
        word
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func escapeTSVField(_ field: String) -> String {
        field
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private static func escapeCSVField(_ field: String) -> String {
        let normalized = field.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.contains(",") || normalized.contains("\"") || normalized.contains("\n") || normalized.contains("\r") else {
            return normalized
        }

        return "\"\(normalized.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
