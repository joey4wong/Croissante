import Foundation

public struct SimpleWord: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let word: String
    public let displayWord: String
    public let tag: String
    public let senseIndex: Int
    public let auxiliary: String
    public let translationZh: String
    public let translationEn: String
    public let exampleFr: String
    public let exampleEn: String
    public let exampleZh: String
    public let nounUICorner: String
    public let nounUIFlags: [String]
    public let nounUIEntityType: String
    public let createdAt: Date

    public enum CodingKeys: String, CodingKey {
        case id
        case word
        case displayWord = "display_word"
        case tag
        case senseIndex = "sense_index"
        case auxiliary
        case translationZh = "translation_zh"
        case translationEn = "translation_en"
        case exampleFr = "example_fr"
        case exampleEn = "example_en"
        case exampleZh = "example_zh"
        case nounUICorner = "noun_ui_corner"
        case nounUIFlags = "noun_ui_flags"
        case nounUIEntityType = "noun_ui_entity_type"
        case createdAt = "created_at"
    }

    public init(
        id: String,
        word: String,
        tag: String = "",
        translationZh: String = "",
        translationEn: String = "",
        exampleFr: String = "",
        exampleEn: String = "",
        exampleZh: String = "",
        displayWord: String? = nil,
        senseIndex: Int = 1,
        auxiliary: String = "",
        nounUICorner: String = "not_applicable",
        nounUIFlags: [String] = [],
        nounUIEntityType: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.word = word
        self.displayWord = Self.firstNonEmpty(displayWord, word)
        self.tag = tag
        self.senseIndex = max(1, senseIndex)
        self.auxiliary = auxiliary
        self.translationZh = translationZh
        self.translationEn = translationEn
        self.exampleFr = exampleFr
        self.exampleEn = exampleEn
        self.exampleZh = exampleZh
        self.nounUICorner = nounUICorner
        self.nounUIFlags = nounUIFlags
        self.nounUIEntityType = nounUIEntityType
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedWord = Self.firstNonEmpty(
            try c.decodeIfPresent(String.self, forKey: .word),
            try c.decodeIfPresent(String.self, forKey: .displayWord)
        )
        word = decodedWord
        displayWord = Self.firstNonEmpty(try c.decodeIfPresent(String.self, forKey: .displayWord), decodedWord)
        tag = try c.decodeIfPresent(String.self, forKey: .tag) ?? ""
        senseIndex = max(1, try c.decodeIfPresent(Int.self, forKey: .senseIndex) ?? 1)
        auxiliary = (try c.decodeIfPresent(String.self, forKey: .auxiliary) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        translationZh = try c.decodeIfPresent(String.self, forKey: .translationZh) ?? ""
        translationEn = try c.decodeIfPresent(String.self, forKey: .translationEn) ?? ""
        exampleFr = try c.decodeIfPresent(String.self, forKey: .exampleFr) ?? ""
        exampleEn = try c.decodeIfPresent(String.self, forKey: .exampleEn) ?? ""
        exampleZh = try c.decodeIfPresent(String.self, forKey: .exampleZh) ?? ""
        nounUICorner = (try c.decodeIfPresent(String.self, forKey: .nounUICorner) ?? "not_applicable")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        nounUIFlags = (try c.decodeIfPresent([String].self, forKey: .nounUIFlags) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        nounUIEntityType = (try c.decodeIfPresent(String.self, forKey: .nounUIEntityType) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        if let decodedId = try c.decodeIfPresent(String.self, forKey: .id)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !decodedId.isEmpty {
            id = decodedId
        } else {
            id = Self.syntheticID(headword: word, senseIndex: senseIndex, tag: tag, displayWord: displayWord)
        }
    }

    public static func makeID(for form: String) -> String {
        "u_\(idPart(form.lowercased()))_\(UUID().uuidString.prefix(8))"
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
