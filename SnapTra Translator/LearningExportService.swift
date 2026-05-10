import Foundation

enum LearningExportFormat: CaseIterable {
    case ankiTSV
    case csv

    var displayName: String {
        switch self {
        case .ankiTSV:
            return "Anki TSV"
        case .csv:
            return "CSV"
        }
    }

    var fileExtension: String {
        switch self {
        case .ankiTSV:
            return "tsv"
        case .csv:
            return "csv"
        }
    }
}

protocol LearningExportRecord {
    var exportWord: String { get }
    var exportDefinitionText: String? { get }
    var exportLookupCount: Int { get }
    var exportReviewStage: Int { get }
    var exportIsMastered: Bool { get }
}

extension WordRecord: LearningExportRecord {
    var exportWord: String { word }
    var exportDefinitionText: String? { definitionText }
    var exportLookupCount: Int { lookupCount }
    var exportReviewStage: Int { reviewStage }
    var exportIsMastered: Bool { isMastered }
}

struct LearningExportRow: Equatable {
    var word: String
    var definitionText: String
    var lookupCount: Int
    var reviewStage: Int
    var isMastered: Bool

    init(record: any LearningExportRecord) {
        self.word = record.exportWord
        self.definitionText = record.exportDefinitionText ?? ""
        self.lookupCount = record.exportLookupCount
        self.reviewStage = record.exportReviewStage
        self.isMastered = record.exportIsMastered
    }

    init(
        word: String,
        definitionText: String,
        lookupCount: Int,
        reviewStage: Int,
        isMastered: Bool
    ) {
        self.word = word
        self.definitionText = definitionText
        self.lookupCount = lookupCount
        self.reviewStage = reviewStage
        self.isMastered = isMastered
    }
}

enum LearningExportService {
    static func export(rows: [LearningExportRow], format: LearningExportFormat) -> String {
        switch format {
        case .ankiTSV:
            return tabSeparated(rows: rows)
        case .csv:
            return commaSeparated(rows: rows)
        }
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
        let header = ["Word", "Definition", "Lookup Count", "Review Stage", "Mastered"]
        let lines = [header.map(escape).joined(separator: separator)] + rows.map { row in
            [
                row.word,
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
