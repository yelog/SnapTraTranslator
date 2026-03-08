import Foundation

/// 词典条目，包含单词的完整词典信息
struct DictionaryEntry: Equatable {
    enum Source: Equatable {
        case advancedDictionary  // ECDICT
        case wordNet             // WordNet English-English
        case systemDictionary    // macOS system dictionary
    }

    let word: String
    let phonetic: String?
    let definitions: [Definition]
    let source: Source
    let synonyms: [String]  // 同义词列表

    /// 单个词义定义
    struct Definition: Equatable {
        let partOfSpeech: String      // 词性：noun, verb, adjective 等
        let field: String?            // 学科/专业领域标记：[医], [法] 等
        let meaning: String            // 英文释义
        let translation: String?       // 中文翻译（来自 Translation API）
        let examples: [String]         // 例句
    }

    /// 是否有有效的词典数据
    var hasDefinitions: Bool {
        !definitions.isEmpty
    }

    /// 获取第一个释义的翻译（用于简洁显示）
    var primaryTranslation: String? {
        definitions.first?.translation
    }

    /// 获取第一个音标
    var primaryPhonetic: String? {
        phonetic
    }

    /// 是否有同义词
    var hasSynonyms: Bool {
        !synonyms.isEmpty
    }
}
