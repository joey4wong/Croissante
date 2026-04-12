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
    let word: String
    let tag: String
    let level: String
    let exampleFr: String
    let isLocked: Bool
    let isEmpty: Bool
}

struct DailyWordProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyWordEntry {
        DailyWordEntry(
            date: .now, word: "bonjour", tag: "INTJ", level: "A1",
            exampleFr: "Bonjour, comment allez-vous ?", isLocked: false, isEmpty: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyWordEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyWordEntry>) -> Void) {
        guard isMemberUnlocked else {
            let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
            completion(Timeline(entries: [lockedEntry(date: .now)], policy: .after(next)))
            return
        }

        var entries: [DailyWordEntry] = []
        let pool = loadPool()
        let now = Date()
        for i in 0..<max(pool.count, 1) {
            let entryDate = Calendar.current.date(byAdding: .hour, value: i, to: now) ?? now
            if pool.isEmpty {
                entries.append(emptyEntry(date: entryDate))
            } else {
                let w = pool[i % pool.count]
                entries.append(entry(for: w, date: entryDate))
            }
        }
        let next = Calendar.current.date(byAdding: .hour, value: entries.count, to: now) ?? now
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
        return entry(for: w, date: .now)
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

    private func loadPool() -> [WidgetWordData] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: DailyWordWidgetDefaults.wordPoolKey),
              let words = try? JSONDecoder().decode([WidgetWordData].self, from: data)
        else { return [] }
        return words.shuffled()
    }

    private func entry(for word: WidgetWordData, date: Date) -> DailyWordEntry {
        DailyWordEntry(
            date: date,
            word: word.word,
            tag: word.tag,
            level: word.level,
            exampleFr: word.exampleFr,
            isLocked: false,
            isEmpty: false
        )
    }

    private func emptyEntry(date: Date) -> DailyWordEntry {
        DailyWordEntry(
            date: date,
            word: "croissant",
            tag: "N",
            level: "A1",
            exampleFr: "",
            isLocked: false,
            isEmpty: true
        )
    }

    private func lockedEntry(date: Date) -> DailyWordEntry {
        DailyWordEntry(
            date: date,
            word: "Croissante Plus",
            tag: "",
            level: "",
            exampleFr: "Open Croissante to unlock widgets.",
            isLocked: true,
            isEmpty: false
        )
    }
}

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

struct DailyWordWidgetView: View {
    var entry: DailyWordEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    private var surfaceColor: Color {
        isDark ? Color(red: 0.15, green: 0.14, blue: 0.15) : Color(red: 0.965, green: 0.966, blue: 0.972)
    }
    private var borderColor: Color {
        isDark ? Color.white.opacity(0.14) : Color.white.opacity(0.72)
    }
    private var glowColor: Color {
        isDark ? Color(red: 0.31, green: 1.00, blue: 0.66) : Color(red: 0.51, green: 0.86, blue: 0.75)
    }
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
    private var bgGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color(red: 0.11, green: 0.10, blue: 0.11), Color(red: 0.05, green: 0.05, blue: 0.06)]
                : [Color(red: 0.96, green: 0.97, blue: 0.99), Color(red: 0.93, green: 0.95, blue: 0.97)],
            startPoint: .top, endPoint: .bottom
        )
    }

    var body: some View {
        Group {
            if entry.isLocked {
                lockedView
            } else {
                switch family {
                case .systemSmall:
                    smallView
                case .systemMedium:
                    mediumView
                default:
                    mediumView
                }
            }
        }
        .containerBackground(for: .widget) { bgGradient }
    }

    private var lockedView: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: family == .systemSmall ? 14 : 16, weight: .semibold))
                    .foregroundStyle(headlineColor.opacity(0.78))

                Text("Croissante Plus")
                    .font(.system(size: family == .systemSmall ? 17 : 19, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(headlineColor)
            }

            Text(entry.exampleFr)
                .font(.system(size: family == .systemSmall ? 12 : 14, weight: .regular))
                .lineLimit(family == .systemSmall ? 3 : 2)
                .foregroundStyle(exampleColor)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(4)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(entry.level.uppercased()).\(posLabelWidget(entry.tag))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(levelColor)

            Text(entry.word)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(headlineColor)

            if !entry.exampleFr.isEmpty {
                Text(entry.exampleFr)
                    .font(.system(size: 11, weight: .regular))
                    .lineLimit(3)
                    .foregroundStyle(exampleColor)
                    .padding(.top, 6)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(4)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(entry.level.uppercased()).\(posLabelWidget(entry.tag))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(levelColor)

            Text(entry.word)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(headlineColor)

            if !entry.exampleFr.isEmpty {
                Text(entry.exampleFr)
                    .font(.system(size: 14, weight: .regular))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(exampleColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
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
