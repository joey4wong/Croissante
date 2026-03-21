import Foundation

struct WidgetWordData: Codable {
    let id: String
    let word: String
    let tag: String
    let level: String
    let translationEn: String
    let translationZh: String
    let exampleFr: String
    let exampleEn: String
    let exampleZh: String
}

enum WidgetDataService {
    static let appGroupId = "group.com.jw.Croissante"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    static func writeWidgetPool(_ words: [WidgetWordData], language: String, level: String) {
        guard let defaults = sharedDefaults,
              let data = try? JSONEncoder().encode(words) else { return }
        defaults.set(data, forKey: "widget_word_pool")
        defaults.set(language, forKey: "widget_language")
        defaults.set(level, forKey: "widget_level")
    }
}
