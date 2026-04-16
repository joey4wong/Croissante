import Foundation

enum LearningMemoryState: String, Codable {
    case forgot
    case blurry
    case mastered
}

/// 单一权威字段是 `intervalDays`（当前复习间隔，0 表示未掌握）。
/// `memoryState` 和“毕业”等概念均由 `intervalDays` 派生，不再单独存储。
struct LearningRecord: Codable {
    let wordId: String
    let intervalDays: Int
    let nextReviewDate: Date
    let lastReviewedAt: Date?

    /// Progress 页桶位由间隔区间派生：
    /// - 0      → forgot
    /// - 1...7  → blurry
    /// - ≥ 8    → mastered
    var memoryState: LearningMemoryState {
        if intervalDays == 0 { return .forgot }
        if intervalDays < 8 { return .blurry }
        return .mastered
    }

    enum CodingKeys: String, CodingKey {
        case wordId
        case intervalDays
        case nextReviewDate
        case lastReviewedAt
        // 兼容开发阶段可能残留的旧字段；读到就做一次性转换，之后不再写。
        case consecutiveCorrects
    }

    private static let iso8601WithFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let iso8601WithoutFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    init(
        wordId: String,
        intervalDays: Int,
        nextReviewDate: Date,
        lastReviewedAt: Date? = nil
    ) {
        self.wordId = wordId
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

        if let directInterval = try container.decodeIfPresent(Int.self, forKey: .intervalDays) {
            self.intervalDays = max(0, directInterval)
        } else if let legacyCC = try container.decodeIfPresent(Int.self, forKey: .consecutiveCorrects) {
            self.intervalDays = Self.intervalFromLegacyConsecutiveCorrects(legacyCC)
        } else {
            self.intervalDays = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wordId, forKey: .wordId)
        try container.encode(intervalDays, forKey: .intervalDays)
        try container.encode(nextReviewDate.formatted(Self.iso8601WithFractionalSeconds), forKey: .nextReviewDate)
        try Self.encodeDateIfPresent(lastReviewedAt, into: &container, forKey: .lastReviewedAt)
    }

    /// 开发阶段兼容：把旧的 `consecutiveCorrects` 映射到最接近的 interval 阶梯值。
    /// 上线后没有用户，这条仅服务于你自己的开发机残留数据。
    private static func intervalFromLegacyConsecutiveCorrects(_ cc: Int) -> Int {
        switch cc {
        case ..<1: return 0
        case 1:    return 1
        case 2:    return 2
        case 3:    return 4
        case 4:    return 8
        default:   return 15 // cc >= 5（旧毕业）→ 映到 mastered 区间首值
        }
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
