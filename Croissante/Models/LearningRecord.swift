import Foundation

struct LearningRecord: Codable {
    let wordId: String
    let consecutiveCorrects: Int
    let nextReviewDate: Date
    
    enum CodingKeys: String, CodingKey {
        case wordId
        case consecutiveCorrects
        case nextReviewDate
    }

    private static let iso8601WithFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let iso8601WithoutFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    
    init(wordId: String, consecutiveCorrects: Int, nextReviewDate: Date) {
        self.wordId = wordId
        self.consecutiveCorrects = consecutiveCorrects
        self.nextReviewDate = nextReviewDate
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.wordId = try container.decode(String.self, forKey: .wordId)
        self.consecutiveCorrects = try container.decode(Int.self, forKey: .consecutiveCorrects)
        
        let dateString = try container.decode(String.self, forKey: .nextReviewDate)
        if let parsed = try? Date(dateString, strategy: Self.iso8601WithFractionalSeconds) {
            self.nextReviewDate = parsed
            return
        }
        if let parsed = try? Date(dateString, strategy: Self.iso8601WithoutFractionalSeconds) {
            self.nextReviewDate = parsed
            return
        }
        self.nextReviewDate = Date()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wordId, forKey: .wordId)
        try container.encode(consecutiveCorrects, forKey: .consecutiveCorrects)
        
        let dateString = nextReviewDate.formatted(Self.iso8601WithFractionalSeconds)
        try container.encode(dateString, forKey: .nextReviewDate)
    }
}
