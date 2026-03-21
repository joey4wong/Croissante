import Foundation

// MARK: - SimpleWord Model

public struct SimpleWord: Identifiable, Codable {
    public let id: String
    public let word: String
    public let tag: String
    public let level: String
    public let translationZh: String
    public let translationEn: String
    public let translationHi: String
    public let exampleFr: String
    public let exampleEn: String
    public let exampleZh: String
    public let exampleHi: String
    
    public enum CodingKeys: String, CodingKey {
        case id
        case word
        case tag
        case level
        case translationZh = "translation_zh"
        case translationEn = "translation_en"
        case translationHi = "translation_hi"
        case exampleFr = "example_fr"
        case exampleEn = "example_en"
        case exampleZh = "example_zh"
        case exampleHi = "example_hi"
        case example1Fr = "example1_fr"
        case example1En = "example1_en"
        case example1Zh = "example1_zh"
        case example1Hi = "example1_hi"
        case example2Fr = "example2_fr"
        case example2En = "example2_en"
        case example2Zh = "example2_zh"
        case example2Hi = "example2_hi"
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
        exampleHi: String = ""
    ) {
        self.id = id
        self.word = word
        self.tag = tag
        self.level = level
        self.translationZh = translationZh
        self.translationEn = translationEn
        self.translationHi = translationHi
        self.exampleFr = exampleFr
        self.exampleEn = exampleEn
        self.exampleZh = exampleZh
        self.exampleHi = exampleHi
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        tag = try container.decode(String.self, forKey: .tag)
        level = try container.decode(String.self, forKey: .level)
        translationZh = try container.decode(String.self, forKey: .translationZh)
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
            try container.decodeIfPresent(String.self, forKey: .example1Zh),
            try container.decodeIfPresent(String.self, forKey: .example2Zh)
        )
        exampleHi = Self.firstNonEmpty(
            try container.decodeIfPresent(String.self, forKey: .exampleHi),
            try container.decodeIfPresent(String.self, forKey: .example1Hi),
            try container.decodeIfPresent(String.self, forKey: .example2Hi)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(word, forKey: .word)
        try container.encode(tag, forKey: .tag)
        try container.encode(level, forKey: .level)
        try container.encode(translationZh, forKey: .translationZh)
        try container.encode(translationEn, forKey: .translationEn)
        try container.encode(translationHi, forKey: .translationHi)
        try container.encode(exampleFr, forKey: .exampleFr)
        try container.encode(exampleEn, forKey: .exampleEn)
        try container.encode(exampleZh, forKey: .exampleZh)
        try container.encode(exampleHi, forKey: .exampleHi)
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }
}
