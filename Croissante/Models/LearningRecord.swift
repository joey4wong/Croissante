import Foundation

enum LearningMemoryState: String, Codable {
    case forgot
    case blurry
    case mastered
}

enum SRSRules {
    static let masteredIntervalThreshold = 8
    static let masteryLadder = [1, 2, 4, 8, 15, 30]
}

/// `memoryState` 是用户宣告的桶归属（UI 显示用），`intervalDays` 是 SRS 下次复习调度（节奏用），两者独立。
struct LearningRecord: Codable {
    let wordId: String
    let memoryState: LearningMemoryState
    let intervalDays: Int
    let nextReviewDate: Date
    let lastReviewedAt: Date?

    enum CodingKeys: String, CodingKey {
        case wordId
        case memoryState
        case intervalDays
        case nextReviewDate
        case lastReviewedAt
    }

    private static let iso8601WithFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let iso8601WithoutFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    init(
        wordId: String,
        memoryState: LearningMemoryState,
        intervalDays: Int,
        nextReviewDate: Date,
        lastReviewedAt: Date? = nil
    ) {
        self.wordId = wordId
        self.memoryState = memoryState
        self.intervalDays = max(0, intervalDays)
        self.nextReviewDate = nextReviewDate
        self.lastReviewedAt = lastReviewedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.wordId = try container.decode(String.self, forKey: .wordId)

        let dateString = try container.decode(String.self, forKey: .nextReviewDate)
        self.nextReviewDate = Self.parseDate(dateString) ?? Date()
        self.lastReviewedAt = Self.decodeDateIfPresent(from: container, forKey: .lastReviewedAt)

        let interval = max(0, try container.decodeIfPresent(Int.self, forKey: .intervalDays) ?? 0)
        self.intervalDays = interval

        if let stored = try container.decodeIfPresent(LearningMemoryState.self, forKey: .memoryState) {
            self.memoryState = stored
        } else {
            // 旧记录未写字段时的回退：按 interval 派生一次，之后落盘即固化。
            if interval == 0 {
                self.memoryState = .forgot
            } else if interval < SRSRules.masteredIntervalThreshold {
                self.memoryState = .blurry
            } else {
                self.memoryState = .mastered
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wordId, forKey: .wordId)
        try container.encode(memoryState, forKey: .memoryState)
        try container.encode(intervalDays, forKey: .intervalDays)
        try container.encode(nextReviewDate.formatted(Self.iso8601WithFractionalSeconds), forKey: .nextReviewDate)
        try Self.encodeDateIfPresent(lastReviewedAt, into: &container, forKey: .lastReviewedAt)
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
