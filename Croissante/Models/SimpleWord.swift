import Foundation

// MARK: - SimpleWord Model

public struct SimpleWord: Identifiable, Codable, Sendable {
    public let id: String
    public let word: String
    public let displayWord: String
    public let tag: String
    public let level: String
    public let senseIndex: Int
    public let auxiliary: String
    public let translationZh: String
    public let translationEn: String
    public let translationHi: String
    public let exampleFr: String
    public let exampleEn: String
    public let exampleZh: String
    public let exampleHi: String
    public let nounUICorner: String
    public let nounUIFlags: [String]
    public let nounUIEntityType: String
    
    public enum CodingKeys: String, CodingKey {
        case id
        case word
        case form
        case headword
        case displayWord = "display_word"
        case tag
        case pos
        case level
        case senseIndex = "sense_index"
        case auxiliary
        case translationZh = "translation_zh"
        case translationCn = "translation_cn"
        case translationEn = "translation_en"
        case translationHi = "translation_hi"
        case exampleFr = "example_fr"
        case exampleEn = "example_en"
        case exampleZh = "example_zh"
        case exampleCn = "example_cn"
        case exampleHi = "example_hi"
        case example1Fr = "example1_fr"
        case example1En = "example1_en"
        case example1Zh = "example1_zh"
        case example1Hi = "example1_hi"
        case example2Fr = "example2_fr"
        case example2En = "example2_en"
        case example2Zh = "example2_zh"
        case example2Hi = "example2_hi"
        case nounUICorner = "noun_ui_corner"
        case nounUIFlags = "noun_ui_flags"
        case nounUIEntityType = "noun_ui_entity_type"
    }
    
    public init(
        id: String,
        word: String,
        tag: String,
        level: String,
        translationZh: String,
        translationEn: String,
        translationHi: String = "",
        exampleFr: String,
        exampleEn: String = "",
        exampleZh: String,
        exampleHi: String = "",
        displayWord: String? = nil,
        senseIndex: Int = 1,
        auxiliary: String = "",
        nounUICorner: String = "not_applicable",
        nounUIFlags: [String] = [],
        nounUIEntityType: String = ""
    ) {
        self.id = id
        self.word = word
        self.displayWord = Self.firstNonEmpty(displayWord, word)
        self.tag = tag
        self.level = level
        self.senseIndex = max(1, senseIndex)
        self.auxiliary = auxiliary
        self.translationZh = translationZh
        self.translationEn = translationEn
        self.translationHi = translationHi
        self.exampleFr = exampleFr
        self.exampleEn = exampleEn
        self.exampleZh = exampleZh
        self.exampleHi = exampleHi
        self.nounUICorner = nounUICorner
        self.nounUIFlags = nounUIFlags
        self.nounUIEntityType = nounUIEntityType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedWord = Self.firstNonEmpty(
            try container.decodeIfPresent(String.self, forKey: .word),
            try container.decodeIfPresent(String.self, forKey: .form),
            try container.decodeIfPresent(String.self, forKey: .headword),
            try container.decodeIfPresent(String.self, forKey: .displayWord)
        )
        word = decodedWord
        displayWord = Self.firstNonEmpty(
            try container.decodeIfPresent(String.self, forKey: .displayWord),
            decodedWord
        )
        tag = Self.firstNonEmpty(
            try container.decodeIfPresent(String.self, forKey: .tag),
            try container.decodeIfPresent(String.self, forKey: .pos)
        )
        level = try container.decode(String.self, forKey: .level)
        senseIndex = max(1, try container.decodeIfPresent(Int.self, forKey: .senseIndex) ?? 1)
        auxiliary = (try container.decodeIfPresent(String.self, forKey: .auxiliary) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        translationZh = Self.firstNonEmpty(
            try container.decodeIfPresent(String.self, forKey: .translationZh),
            try container.decodeIfPresent(String.self, forKey: .translationCn)
        )
        translationEn = try container.decode(String.self, forKey: .translationEn)
        translationHi = try container.decodeIfPresent(String.self, forKey: .translationHi) ?? ""

        exampleFr = Self.firstNonEmpty(
            try container.decodeIfPresent(String.self, forKey: .exampleFr),
            try container.decodeIfPresent(String.self, forKey: .example1Fr),
            try container.decodeIfPresent(String.self, forKey: .example2Fr)
        )
        exampleEn = Self.firstNonEmpty(
            try container.decodeIfPresent(String.self, forKey: .exampleEn),
            try container.decodeIfPresent(String.self, forKey: .example1En),
            try container.decodeIfPresent(String.self, forKey: .example2En)
        )
        exampleZh = Self.firstNonEmpty(
            try container.decodeIfPresent(String.self, forKey: .exampleZh),
            try container.decodeIfPresent(String.self, forKey: .exampleCn),
            try container.decodeIfPresent(String.self, forKey: .example1Zh),
            try container.decodeIfPresent(String.self, forKey: .example2Zh)
        )
        exampleHi = Self.firstNonEmpty(
            try container.decodeIfPresent(String.self, forKey: .exampleHi),
            try container.decodeIfPresent(String.self, forKey: .example1Hi),
            try container.decodeIfPresent(String.self, forKey: .example2Hi)
        )
        nounUICorner = (try container.decodeIfPresent(String.self, forKey: .nounUICorner) ?? "not_applicable")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        nounUIFlags = (try container.decodeIfPresent([String].self, forKey: .nounUIFlags) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        nounUIEntityType = (try container.decodeIfPresent(String.self, forKey: .nounUIEntityType) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let decodedId = try container.decodeIfPresent(String.self, forKey: .id)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !decodedId.isEmpty {
            id = decodedId
        } else {
            id = Self.syntheticID(
                headword: word,
                senseIndex: senseIndex,
                tag: tag,
                displayWord: displayWord
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(word, forKey: .word)
        try container.encode(displayWord, forKey: .displayWord)
        try container.encode(tag, forKey: .tag)
        try container.encode(level, forKey: .level)
        try container.encode(senseIndex, forKey: .senseIndex)
        try container.encode(auxiliary, forKey: .auxiliary)
        try container.encode(translationZh, forKey: .translationZh)
        try container.encode(translationEn, forKey: .translationEn)
        try container.encode(translationHi, forKey: .translationHi)
        try container.encode(exampleFr, forKey: .exampleFr)
        try container.encode(exampleEn, forKey: .exampleEn)
        try container.encode(exampleZh, forKey: .exampleZh)
        try container.encode(exampleHi, forKey: .exampleHi)
        try container.encode(nounUICorner, forKey: .nounUICorner)
        try container.encode(nounUIFlags, forKey: .nounUIFlags)
        try container.encode(nounUIEntityType, forKey: .nounUIEntityType)
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private static func syntheticID(headword: String, senseIndex: Int, tag: String, displayWord: String) -> String {
        "w_\(idPart(headword))_\(senseIndex)_\(idPart(tag))_\(idPart(displayWord))"
    }

    private static func idPart(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "na" }
        return trimmed
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: " ", with: "_")
    }
}
