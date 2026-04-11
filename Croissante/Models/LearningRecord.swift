import Foundation

enum LearningMemoryState: String, Codable {
    case forgot
    case blurry
    case mastered
}

struct LearningRecord: Codable {
    let wordId: String
    let consecutiveCorrects: Int
    let nextReviewDate: Date
    let memoryState: LearningMemoryState
    let lastReviewedAt: Date?
    let lastMistakeAt: Date?
    let forgotCount: Int
    let blurryCount: Int
    let successfulReviewsSinceMistake: Int
    
    enum CodingKeys: String, CodingKey {
        case wordId
        case consecutiveCorrects
        case nextReviewDate
        case memoryState
        case lastReviewedAt
        case lastMistakeAt
        case forgotCount
        case blurryCount
        case successfulReviewsSinceMistake
    }

    private static let iso8601WithFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let iso8601WithoutFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    
    init(
        wordId: String,
        consecutiveCorrects: Int,
        nextReviewDate: Date,
        memoryState: LearningMemoryState = .mastered,
        lastReviewedAt: Date? = nil,
        lastMistakeAt: Date? = nil,
        forgotCount: Int = 0,
        blurryCount: Int = 0,
        successfulReviewsSinceMistake: Int = 0
    ) {
        self.wordId = wordId
        self.consecutiveCorrects = max(0, consecutiveCorrects)
        self.nextReviewDate = nextReviewDate
        self.memoryState = memoryState
        self.lastReviewedAt = lastReviewedAt
        self.lastMistakeAt = lastMistakeAt
        self.forgotCount = max(0, forgotCount)
        self.blurryCount = max(0, blurryCount)
        self.successfulReviewsSinceMistake = max(0, successfulReviewsSinceMistake)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.wordId = try container.decode(String.self, forKey: .wordId)
        self.consecutiveCorrects = max(0, try container.decode(Int.self, forKey: .consecutiveCorrects))
        
        let dateString = try container.decode(String.self, forKey: .nextReviewDate)
        self.nextReviewDate = Self.parseDate(dateString) ?? Date()
        self.memoryState = Self.decodeMemoryState(from: container) ?? .mastered
        self.lastReviewedAt = Self.decodeDateIfPresent(from: container, forKey: .lastReviewedAt)
        self.lastMistakeAt = Self.decodeDateIfPresent(from: container, forKey: .lastMistakeAt)
        self.forgotCount = max(0, (try? container.decodeIfPresent(Int.self, forKey: .forgotCount)) ?? 0)
        self.blurryCount = max(0, (try? container.decodeIfPresent(Int.self, forKey: .blurryCount)) ?? 0)
        self.successfulReviewsSinceMistake = max(0, (try? container.decodeIfPresent(Int.self, forKey: .successfulReviewsSinceMistake)) ?? 0)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wordId, forKey: .wordId)
        try container.encode(consecutiveCorrects, forKey: .consecutiveCorrects)
        
        let dateString = nextReviewDate.formatted(Self.iso8601WithFractionalSeconds)
        try container.encode(dateString, forKey: .nextReviewDate)
        try container.encode(memoryState.rawValue, forKey: .memoryState)
        try Self.encodeDateIfPresent(lastReviewedAt, into: &container, forKey: .lastReviewedAt)
        try Self.encodeDateIfPresent(lastMistakeAt, into: &container, forKey: .lastMistakeAt)
        try container.encode(forgotCount, forKey: .forgotCount)
        try container.encode(blurryCount, forKey: .blurryCount)
        try container.encode(successfulReviewsSinceMistake, forKey: .successfulReviewsSinceMistake)
    }

    private static func decodeMemoryState(from container: KeyedDecodingContainer<CodingKeys>) -> LearningMemoryState? {
        guard let rawValue = try? container.decodeIfPresent(String.self, forKey: .memoryState) else {
            return nil
        }
        return LearningMemoryState(rawValue: rawValue)
    }

    private static func decodeDateIfPresent(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Date? {
        guard let dateString = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return parseDate(dateString)
    }

    private static func encodeDateIfPresent(
        _ date: Date?,
        into container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        guard let date else { return }
        try container.encode(date.formatted(Self.iso8601WithFractionalSeconds), forKey: key)
    }

    private static func parseDate(_ dateString: String) -> Date? {
        if let parsed = try? Date(dateString, strategy: Self.iso8601WithFractionalSeconds) {
            return parsed
        }
        if let parsed = try? Date(dateString, strategy: Self.iso8601WithoutFractionalSeconds) {
            return parsed
        }
        return nil
    }
}
