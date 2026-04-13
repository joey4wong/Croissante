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
    let translationEn: String
    let translationZh: String
    let translationHi: String?
    let exampleFr: String
    let exampleEn: String
    let exampleZh: String
    let exampleHi: String?
}

private struct WidgetCardMetrics {
    let scale: CGFloat
    let titleBaseFontSize: CGFloat
    let isSmall: Bool

    init(family: WidgetFamily, size: CGSize, word: String) {
        // Mirrors the homepage card baseline: 393pt width, 24pt side padding, width - 72 content height.
        let referenceContentWidth: CGFloat = 345
        let referenceContentHeight: CGFloat = 321
        let availableWidth = max(size.width, 1)
        let availableHeight = max(size.height, 1)
        scale = min(availableWidth / referenceContentWidth, availableHeight / referenceContentHeight)

        let count = word.count
        if count >= 24 {
            titleBaseFontSize = 42
        } else if count >= 20 {
            titleBaseFontSize = 46
        } else if count >= 16 {
            titleBaseFontSize = 50
        } else {
            titleBaseFontSize = 56
        }

        isSmall = family == .systemSmall
    }

    func scaled(_ value: CGFloat) -> CGFloat {
        value * scale
    }

    func fontSize(_ value: CGFloat, minimum: CGFloat) -> CGFloat {
        max(scaled(value), minimum)
    }

    var horizontalPadding: CGFloat { max(4, scaled(24)) }
    var verticalPadding: CGFloat { max(4, scaled(24)) }
    var headerSpacing: CGFloat { max(1, scaled(4)) }
    var headerBottomPadding: CGFloat { max(2, scaled(16)) }
    var titleBottomPadding: CGFloat { max(2, scaled(20)) }
    var dividerBottomPadding: CGFloat { max(3, scaled(20)) }
    var exampleTopPadding: CGFloat { max(4, scaled(18)) }
    var exampleSpacing: CGFloat { max(2, scaled(4)) }
    var detailSpacing: CGFloat { max(6, scaled(10)) }
    var levelFontSize: CGFloat { fontSize(10, minimum: isSmall ? 8.5 : 9.5) }
    var titleFontSize: CGFloat { fontSize(titleBaseFontSize, minimum: isSmall ? 24 : 30) }
    var posFontSize: CGFloat { fontSize(16, minimum: isSmall ? 10.5 : 12.5) }
    var translationFontSize: CGFloat { fontSize(16, minimum: isSmall ? 10.5 : 12.5) }
    var exampleFontSize: CGFloat { fontSize(16, minimum: isSmall ? 10.5 : 12.5) }
    var exampleTranslationFontSize: CGFloat { fontSize(15, minimum: isSmall ? 9.5 : 11.5) }
    var titleTracking: CGFloat { scaled(0.2) }
    var levelTracking: CGFloat { scaled(0.7) }
    var levelOpacity: Double { 0.78 }
    var dividerOpacity: Double { 0.64 }
}

struct DailyWordWidgetView: View {
    var entry: DailyWordEntry
    @Environment(\.widgetFamily) var family
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
                scaledCardView
            }
        }
        .containerBackground(for: .widget) { bgGradient }
        .widgetURL(deepLinkURL)
    }

    private var lockedView: some View {
        let side = family == .systemSmall ? CGFloat(56) : 72
        let titleSize = family == .systemSmall ? CGFloat(17) : 22
        let padH = family == .systemSmall ? CGFloat(8) : 16
        return ZStack {
            Image("Croissante00001")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)

            Text(entry.word)
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .foregroundStyle(headlineColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, family == .systemSmall ? 6 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, padH)
    }

    private var scaledCardView: some View {
        GeometryReader { proxy in
            let metrics = WidgetCardMetrics(family: family, size: proxy.size, word: entry.word)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: metrics.headerSpacing) {
                    Text("\(entry.level.uppercased()).\(posLabelWidget(entry.tag))")
                        .font(.system(size: metrics.levelFontSize, weight: .semibold, design: .rounded))
                        .tracking(metrics.levelTracking)
                        .foregroundStyle(levelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(metrics.levelOpacity)

                    Text(entry.word)
                        .font(.system(size: metrics.titleFontSize, weight: .bold, design: .rounded))
                        .tracking(metrics.titleTracking)
                        .lineLimit(1)
                        .minimumScaleFactor(0.42)
                        .allowsTightening(true)
                        .foregroundStyle(headlineColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, metrics.titleBottomPadding)
                }
                .padding(.bottom, metrics.headerBottomPadding)
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: max(0.5, metrics.scaled(1)))
                    .opacity(metrics.dividerOpacity)
                    .padding(.bottom, metrics.dividerBottomPadding)

                VStack(alignment: .leading, spacing: 0) {
                    if !entry.translation.isEmpty || !entry.tag.isEmpty {
                        HStack(alignment: .top, spacing: metrics.detailSpacing) {
                            Text(posLabelWidget(entry.tag))
                                .font(.system(size: metrics.posFontSize, weight: .medium, design: .rounded))
                                .foregroundStyle(secondaryColor)
                                .padding(.top, max(0.5, metrics.scaled(1)))

                            Text(entry.translation)
                                .font(.system(size: metrics.translationFontSize, weight: .regular))
                                .lineSpacing(metrics.scaled(5))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(bodyColor)
                        }
                    }

                    if !entry.exampleFr.isEmpty {
                        Text(entry.exampleFr)
                            .font(.system(size: metrics.exampleFontSize, weight: .regular))
                            .lineSpacing(metrics.scaled(3))
                            .lineLimit(entry.exampleTranslation.isEmpty ? 3 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(exampleColor)
                            .padding(.top, metrics.exampleTopPadding)
                    }

                    if !entry.exampleTranslation.isEmpty {
                        Text(entry.exampleTranslation)
                            .font(.system(size: metrics.exampleTranslationFontSize, weight: .regular))
                            .lineSpacing(metrics.scaled(2))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(secondaryColor)
                            .padding(.top, entry.exampleFr.isEmpty ? metrics.exampleTopPadding : metrics.exampleSpacing)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
