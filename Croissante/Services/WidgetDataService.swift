import Foundation

struct WidgetWordData: Codable {
    let id: String
    let word: String
    let tag: String
    let level: String
    let auxiliary: String?
    let translationEn: String
    let translationZh: String
    let translationHi: String?
    let exampleFr: String
    let exampleEn: String
    let exampleZh: String
    let exampleHi: String?
}

enum WidgetDataService {
    static let appGroupId = "group.com.jw.Croissante"
    static let wordPoolKey = "widget_word_pool"
    static let languageKey = "widget_language"
    static let levelKey = "widget_level"
    static let memberUnlockedKey = "widget_member_unlocked"
    static let memberAccessExpiresAtKey = "widget_member_access_expires_at"
    static let memberAccessNeverExpiresKey = "widget_member_access_never_expires"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    @discardableResult
    static func writeMemberUnlocked(_ memberUnlocked: Bool) -> Bool {
        guard let defaults = sharedDefaults else { return false }
        let previousValue = defaults.object(forKey: memberUnlockedKey) as? Bool
        defaults.set(memberUnlocked, forKey: memberUnlockedKey)
        if !memberUnlocked {
            defaults.removeObject(forKey: memberAccessExpiresAtKey)
            defaults.removeObject(forKey: memberAccessNeverExpiresKey)
        }
        return previousValue != memberUnlocked
    }

    @discardableResult
    static func writeMemberAccess(_ memberUnlocked: Bool, expirationDate: Date?, neverExpires: Bool) -> Bool {
        guard let defaults = sharedDefaults else { return false }
        let previousValue = defaults.object(forKey: memberUnlockedKey) as? Bool
        let previousExpiration = defaults.object(forKey: memberAccessExpiresAtKey) as? Double
        let previousNeverExpires = defaults.object(forKey: memberAccessNeverExpiresKey) as? Bool

        defaults.set(memberUnlocked, forKey: memberUnlockedKey)
        if memberUnlocked {
            if neverExpires {
                defaults.removeObject(forKey: memberAccessExpiresAtKey)
                defaults.set(true, forKey: memberAccessNeverExpiresKey)
            } else if let expirationDate {
                defaults.set(expirationDate.timeIntervalSince1970, forKey: memberAccessExpiresAtKey)
                defaults.set(false, forKey: memberAccessNeverExpiresKey)
            } else {
                defaults.removeObject(forKey: memberAccessExpiresAtKey)
                defaults.set(false, forKey: memberAccessNeverExpiresKey)
            }
        } else {
            defaults.removeObject(forKey: memberAccessExpiresAtKey)
            defaults.removeObject(forKey: memberAccessNeverExpiresKey)
        }

        let currentExpiration = defaults.object(forKey: memberAccessExpiresAtKey) as? Double
        let currentNeverExpires = defaults.object(forKey: memberAccessNeverExpiresKey) as? Bool
        return previousValue != memberUnlocked ||
            previousExpiration != currentExpiration ||
            previousNeverExpires != currentNeverExpires
    }

    static func writeWidgetPool(_ words: [WidgetWordData], language: String, level: String, memberUnlocked: Bool) {
        guard let defaults = sharedDefaults,
              let data = try? JSONEncoder().encode(words) else { return }
        defaults.set(data, forKey: wordPoolKey)
        defaults.set(language, forKey: languageKey)
        defaults.set(level, forKey: levelKey)
        defaults.set(memberUnlocked, forKey: memberUnlockedKey)
        if !memberUnlocked {
            defaults.removeObject(forKey: memberAccessExpiresAtKey)
            defaults.removeObject(forKey: memberAccessNeverExpiresKey)
        }
    }

    static func writeWidgetPool(
        from words: [SimpleWord],
        language: String,
        level: String,
        memberUnlocked: Bool,
        excluding excludedWordIds: Set<String> = []
    ) {
        let filtered = level == "All" ? words : words.filter { $0.level == level }
        let pool = filtered
            .filter { !excludedWordIds.contains($0.id) }
            .shuffled()
            .prefix(50)
            .map { word in
                WidgetWordData(
                    id: word.id,
                    word: word.word,
                    tag: word.tag,
                    level: word.level,
                    auxiliary: word.auxiliary,
                    translationEn: word.translationEn,
                    translationZh: word.translationZh,
                    translationHi: word.translationHi,
                    exampleFr: word.exampleFr,
                    exampleEn: word.exampleEn,
                    exampleZh: word.exampleZh,
                    exampleHi: word.exampleHi
                )
            }

        writeWidgetPool(pool, language: language, level: level, memberUnlocked: memberUnlocked)
    }
}
