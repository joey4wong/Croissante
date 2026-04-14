import Foundation
import WidgetKit
import SwiftUI

private enum DailyWordWidgetDefaults {
    static let appGroupId = "group.com.jw.Croissante"
    static let wordPoolKey = "widget_word_pool"
    static let languageKey = "widget_language"
    static let memberUnlockedKey = "widget_member_unlocked"
    static let memberAccessExpiresAtKey = "widget_member_access_expires_at"
    static let memberAccessNeverExpiresKey = "widget_member_access_never_expires"
}

struct DailyWordEntry: TimelineEntry {
    let date: Date
    let wordId: String
    let word: String
    let tag: String
    let level: String
    let auxiliary: String
    let translation: String
    let exampleFr: String
    let exampleTranslation: String
    let isLocked: Bool
    let isEmpty: Bool
}

struct DailyWordProvider: TimelineProvider {
    private static let entryIntervalMinutes = 5

    func placeholder(in context: Context) -> DailyWordEntry {
        DailyWordEntry(
            date: .now,
            wordId: "w_bonjour",
            word: "bonjour",
            tag: "INTJ",
            level: "A1",
            auxiliary: "",
            translation: "hello",
            exampleFr: "Bonjour, comment allez-vous ?",
            exampleTranslation: "Hello, how are you?",
            isLocked: false,
            isEmpty: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyWordEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyWordEntry>) -> Void) {
        guard isMemberUnlocked else {
            let next = Calendar.current.date(byAdding: .minute, value: Self.entryIntervalMinutes, to: .now) ?? .now
            completion(Timeline(entries: [lockedEntry(date: .now)], policy: .after(next)))
            return
        }

        var entries: [DailyWordEntry] = []
        let pool = loadPool()
        let language = currentLanguage
        let now = Date()
        for i in 0..<max(pool.count, 1) {
            let entryDate = Calendar.current.date(byAdding: .minute, value: Self.entryIntervalMinutes * i, to: now) ?? now
            if pool.isEmpty {
                entries.append(emptyEntry(date: entryDate))
            } else {
                let w = pool[i % pool.count]
                entries.append(entry(for: w, date: entryDate, language: language))
            }
        }
        let next = Calendar.current.date(byAdding: .minute, value: Self.entryIntervalMinutes * entries.count, to: now) ?? now
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func loadEntry() -> DailyWordEntry {
        guard isMemberUnlocked else {
            return lockedEntry(date: .now)
        }

        let pool = loadPool()
        guard !pool.isEmpty else {
            return emptyEntry(date: .now)
        }
        let w = pool.randomElement()!
        return entry(for: w, date: .now, language: currentLanguage)
    }

    private var isMemberUnlocked: Bool {
        guard let defaults = sharedDefaults,
              defaults.bool(forKey: DailyWordWidgetDefaults.memberUnlockedKey) else {
            return false
        }
        if defaults.bool(forKey: DailyWordWidgetDefaults.memberAccessNeverExpiresKey) {
            return true
        }
        let expirationInterval = defaults.double(forKey: DailyWordWidgetDefaults.memberAccessExpiresAtKey)
        guard expirationInterval > 0 else { return false }
        return Date(timeIntervalSince1970: expirationInterval) > Date()
    }

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: DailyWordWidgetDefaults.appGroupId)
    }

    private var currentLanguage: String {
        sharedDefaults?.string(forKey: DailyWordWidgetDefaults.languageKey) ?? "en"
    }

    private func loadPool() -> [WidgetWordData] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: DailyWordWidgetDefaults.wordPoolKey),
              let words = try? JSONDecoder().decode([WidgetWordData].self, from: data)
        else { return [] }
        return words.shuffled()
    }

    private func entry(for word: WidgetWordData, date: Date, language: String) -> DailyWordEntry {
        DailyWordEntry(
            date: date,
            wordId: word.id,
            word: word.word,
            tag: word.tag,
            level: word.level,
            auxiliary: word.auxiliary ?? "",
            translation: translation(for: word, language: language),
            exampleFr: word.exampleFr,
            exampleTranslation: exampleTranslation(for: word, language: language),
            isLocked: false,
            isEmpty: false
        )
    }

    private func emptyEntry(date: Date) -> DailyWordEntry {
        DailyWordEntry(
            date: date,
            wordId: "",
            word: "croissant",
            tag: "N",
            level: "A1",
            auxiliary: "",
            translation: "",
            exampleFr: "",
            exampleTranslation: "",
            isLocked: false,
            isEmpty: true
        )
    }

    private func lockedEntry(date: Date) -> DailyWordEntry {
        DailyWordEntry(
            date: date,
            wordId: "",
            word: "Croissante Plus",
            tag: "",
            level: "",
            auxiliary: "",
            translation: "",
            exampleFr: "",
            exampleTranslation: "",
            isLocked: true,
            isEmpty: false
        )
    }

    private func translation(for word: WidgetWordData, language: String) -> String {
        switch language {
        case "zh": return firstNonEmpty(word.translationZh, word.translationEn, word.translationHi)
        case "hi": return firstNonEmpty(word.translationHi, word.translationEn, word.translationZh)
        default: return firstNonEmpty(word.translationEn, word.translationZh, word.translationHi)
        }
    }

    private func exampleTranslation(for word: WidgetWordData, language: String) -> String {
        switch language {
        case "zh": return firstNonEmpty(word.exampleZh, word.exampleEn, word.exampleHi)
        case "hi": return firstNonEmpty(word.exampleHi, word.exampleEn, word.exampleZh)
        default: return firstNonEmpty(word.exampleEn, word.exampleZh, word.exampleHi)
        }
    }

    private func firstNonEmpty(_ values: String?...) -> String {
        for v in values {
            let t = v?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty { return t }
        }
        return ""
    }
}

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

struct DailyWordWidgetView: View {
    var entry: DailyWordEntry
    @Environment(\.colorScheme) var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    private var headlineColor: Color {
        isDark ? Color.white.opacity(0.92) : Color(red: 0.08, green: 0.11, blue: 0.20)
    }
    private var levelColor: Color {
        isDark ? Color.white.opacity(0.48) : Color.black.opacity(0.30)
    }
    private var bodyColor: Color {
        isDark ? Color.white.opacity(0.80) : Color.black.opacity(0.78)
    }
    private var secondaryColor: Color {
        isDark ? Color.white.opacity(0.64) : Color.black.opacity(0.42)
    }
    private var exampleColor: Color {
        isDark ? Color.white.opacity(0.64) : Color.black.opacity(0.72)
    }
    private var dividerColor: Color {
        isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.14)
    }
    private let levelAuxFont = Font.system(size: 5, weight: .semibold, design: .rounded)
    private var bgGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color(red: 0.11, green: 0.10, blue: 0.11), Color(red: 0.05, green: 0.05, blue: 0.06)]
                : [Color(red: 0.96, green: 0.97, blue: 0.99), Color(red: 0.93, green: 0.95, blue: 0.97)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var deepLinkURL: URL? {
        if entry.isLocked {
            return URL(string: "croissante://paywall")
        }
        guard !entry.isEmpty else { return nil }
        let wordId = entry.wordId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wordId.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "croissante"
        components.host = "word"
        components.queryItems = [URLQueryItem(name: "id", value: wordId)]
        return components.url
    }

    var body: some View {
        Group {
            if entry.isLocked {
                lockedView
            } else {
                smallLayout
            }
        }
        .containerBackground(for: .widget) { bgGradient }
        .widgetURL(deepLinkURL)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.word)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .tracking(0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .allowsTightening(true)
                .foregroundStyle(headlineColor)
                .padding(.bottom, 10)

            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
                .padding(.bottom, 10)

            if !entry.tag.isEmpty || !entry.translation.isEmpty {
                HStack(alignment: .top, spacing: 7) {
                    if !entry.tag.isEmpty {
                        Text(posLabelWidget(entry.tag))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(secondaryColor)
                            .padding(.top, 1)
                    }
                    if !entry.translation.isEmpty {
                        Text(entry.translation)
                            .font(.system(size: 13, weight: .regular))
                            .lineSpacing(4)
                            .lineLimit(2)
                            .foregroundStyle(bodyColor)
                    }
                }
                .padding(.bottom, 8)
            }

            if !entry.exampleFr.isEmpty {
                Text(entry.exampleFr)
                    .font(.system(size: 12, weight: .regular))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .foregroundStyle(exampleColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
            }

            if !entry.exampleTranslation.isEmpty {
                Text(entry.exampleTranslation)
                    .font(.system(size: 11, weight: .regular))
                    .lineSpacing(2)
                    .lineLimit(2)
                    .foregroundStyle(secondaryColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            levelAuxLabel
                .padding(.top, 5)
                .padding(.leading, 10)
        }
    }

    private var lockedView: some View {
        ZStack {
            Image("Croissante00001")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
            Text(entry.word)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .foregroundStyle(headlineColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    // MARK: - Shared helpers

    @ViewBuilder
    private var levelAuxLabel: some View {
        let aux = entry.auxiliary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entry.level.isEmpty || !aux.isEmpty {
            HStack(spacing: 2.5) {
                if !entry.level.isEmpty {
                    Text(entry.level.uppercased())
                        .font(levelAuxFont)
                }
                if !aux.isEmpty {
                    Text("·")
                        .font(levelAuxFont)
                        .opacity(0.6)
                    Text(aux)
                        .font(levelAuxFont)
                }
            }
            .tracking(0.35)
            .foregroundStyle(levelColor)
            .lineLimit(1)
        }
    }

    private func posLabelWidget(_ tag: String) -> String {
        switch tag.uppercased() {
        case "N": return "n."
        case "V": return "v."
        case "A": return "adj."
        case "ADV": return "adv."
        case "INTJ": return "intj."
        case "PREP": return "prep."
        case "CONJ": return "conj."
        case "PRON": return "pron."
        case "DET": return "det."
        case "ART": return "art."
        default: return tag
        }
    }
}

struct DailyWordWidget: Widget {
    let kind = "DailyWordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyWordProvider()) { entry in
            DailyWordWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Word")
        .description("A Croissante Plus daily word at a glance.")
        .supportedFamilies([.systemSmall])
    }
}
