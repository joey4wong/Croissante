enum TTSVoice: String, CaseIterable, Identifiable {
    case frederic
    case koraly
    case theodore
    case marie

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frederic: return "Frédéric"
        case .koraly: return "Koraly"
        case .theodore: return "Théodore"
        case .marie: return "Marie"
        }
    }

    static let `default` = TTSVoice.frederic

    static func normalizedId(_ id: String) -> String {
        TTSVoice(rawValue: id) != nil ? id : TTSVoice.default.rawValue
    }
}
