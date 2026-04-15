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
            translation: "你好",
            exampleFr: "Bonjour, comment allez-vous ?",
            exampleTranslation: "你好，请问你怎么样？",
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

        let pool = loadPool()
        let language = currentLanguage
        let now = Date()
        var entries: [DailyWordEntry] = []

        for i in 0..<max(pool.count, 1) {
            let entryDate = Calendar.current.date(byAdding: .minute, value: Self.entryIntervalMinutes * i, to: now) ?? now
            if pool.isEmpty {
                entries.append(emptyEntry(date: entryDate))
            } else {
                entries.append(entry(for: pool[i % pool.count], date: entryDate, language: language))
            }
        }

        let next = Calendar.current.date(byAdding: .minute, value: Self.entryIntervalMinutes * entries.count, to: now) ?? now
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func loadEntry() -> DailyWordEntry {
        guard isMemberUnlocked else { return lockedEntry(date: .now) }
        let pool = loadPool()
        guard !pool.isEmpty else { return emptyEntry(date: .now) }
        return entry(for: pool.randomElement()!, date: .now, language: currentLanguage)
    }

    private var isMemberUnlocked: Bool {
        guard let defaults = sharedDefaults,
              defaults.bool(forKey: DailyWordWidgetDefaults.memberUnlockedKey) else { return false }
        if defaults.bool(forKey: DailyWordWidgetDefaults.memberAccessNeverExpiresKey) { return true }
        let exp = defaults.double(forKey: DailyWordWidgetDefaults.memberAccessExpiresAtKey)
        guard exp > 0 else { return false }
        return Date(timeIntervalSince1970: exp) > Date()
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
            translation: resolvedTranslation(word, language: language),
            exampleFr: word.exampleFr,
            exampleTranslation: resolvedExampleTranslation(word, language: language),
            isLocked: false,
            isEmpty: false
        )
    }

    private func emptyEntry(date: Date) -> DailyWordEntry {
        DailyWordEntry(
            date: date, wordId: "", word: "croissant", tag: "N", level: "A1",
            auxiliary: "", translation: "", exampleFr: "", exampleTranslation: "",
            isLocked: false, isEmpty: true
        )
    }

    private func lockedEntry(date: Date) -> DailyWordEntry {
        DailyWordEntry(
            date: date, wordId: "", word: "Croissante Plus", tag: "", level: "",
            auxiliary: "", translation: "", exampleFr: "", exampleTranslation: "",
            isLocked: true, isEmpty: false
        )
    }

    private func resolvedTranslation(_ word: WidgetWordData, language: String) -> String {
        switch language {
        case "zh": return firstNonEmpty(word.translationZh, word.translationEn, word.translationHi)
        case "hi": return firstNonEmpty(word.translationHi, word.translationEn, word.translationZh)
        default:   return firstNonEmpty(word.translationEn, word.translationZh, word.translationHi)
        }
    }

    private func resolvedExampleTranslation(_ word: WidgetWordData, language: String) -> String {
        switch language {
        case "zh": return firstNonEmpty(word.exampleZh, word.exampleEn, word.exampleHi)
        case "hi": return firstNonEmpty(word.exampleHi, word.exampleEn, word.exampleZh)
        default:   return firstNonEmpty(word.exampleEn, word.exampleZh, word.exampleHi)
        }
    }

    private func firstNonEmpty(_ values: String?...) -> String {
        for v in values {
            if let t = v?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        }
        return ""
    }
}

// MARK: - View

struct DailyWordWidgetView: View {
    var entry: DailyWordEntry

    private var deepLinkURL: URL? {
        if entry.isLocked { return URL(string: "croissante://paywall") }
        guard !entry.isEmpty, !entry.wordId.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "croissante"; c.host = "word"
        c.queryItems = [URLQueryItem(name: "id", value: entry.wordId)]
        return c.url
    }

    var body: some View {
        mainContent
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [
                        Color(uiColor: .systemBackground),
                        Color(uiColor: .secondarySystemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .widgetURL(deepLinkURL)
    }

    @ViewBuilder
    private var mainContent: some View {
        if entry.isLocked {
            lockedView
        } else {
            wordView
        }
    }

    // MARK: Locked

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
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    // MARK: Main

    private var wordView: some View {
        VStack(alignment: .center, spacing: 0) {
            // French word — centered, large
            Text(entry.word)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.38)
                .allowsTightening(true)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 22)

            Color(uiColor: .separator)
                .frame(height: 1)
                .padding(.top, 5)
                .padding(.bottom, 5)

            // pos + translation
            HStack(alignment: .center, spacing: 4) {
                if !entry.tag.isEmpty {
                    Text(posLabel(entry.tag))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
                if !entry.translation.isEmpty {
                    Text(entry.translation)
                        .font(.system(size: 10, weight: .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                        .allowsTightening(true)
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)

            // example fr
            if !entry.exampleFr.isEmpty {
                Text(entry.exampleFr)
                    .font(.system(size: 9.5, weight: .regular))
                    .lineSpacing(1.2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.80)
                    .allowsTightening(true)
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
            }

            // example translation
            if !entry.exampleTranslation.isEmpty {
                Text(entry.exampleTranslation)
                    .font(.system(size: 9, weight: .regular))
                    .lineSpacing(1.0)
                    .lineLimit(2)
                    .minimumScaleFactor(0.80)
                    .allowsTightening(true)
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topLeading) {
            levelAuxLabel
                .padding(.top, 13)
                .padding(.leading, 13)
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private var levelAuxLabel: some View {
        let aux = entry.auxiliary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entry.level.isEmpty || !aux.isEmpty {
            HStack(spacing: 2) {
                if !entry.level.isEmpty {
                    Text(entry.level.uppercased())
                }
                if !aux.isEmpty {
                    Text("·").opacity(0.5)
                    Text(aux)
                }
            }
            .font(.system(size: 6, weight: .semibold, design: .rounded))
            .tracking(0.3)
            .foregroundStyle(Color.secondary.opacity(0.6))
            .lineLimit(1)
        }
    }

    private func posLabel(_ tag: String) -> String {
        switch tag.uppercased() {
        case "N":    return "n."
        case "V":    return "v."
        case "A":    return "adj."
        case "ADV":  return "adv."
        case "INTJ": return "intj."
        case "PREP": return "prep."
        case "CONJ": return "conj."
        case "PRON": return "pron."
        case "DET":  return "det."
        case "ART":  return "art."
        default:     return tag
        }
    }
}

// MARK: - Widget

struct DailyWordWidget: Widget {
    let kind = "DailyWordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyWordProvider()) { entry in
            DailyWordWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Word")
        .description("A Croissante Plus daily word at a glance.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
