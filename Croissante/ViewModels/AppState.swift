import SwiftUI

public enum ThemeMode: Int, Codable {
    case system = 0
    case dark = 2
    case light = 5
}

public enum CardFontStyle: String, Codable {
    case sfPro
    case sfRounded
    case avenirNext
    case newYork
}

enum SearchTextNormalizer {
    static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    static func normalizeExact(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

fileprivate struct ConjugationFormIndexEntry: Sendable {
    let form: String
    let lemmas: [String]
}

fileprivate struct ConjugationData: Sendable {
    static let empty = ConjugationData(
        map: [:],
        formsByLemma: [:],
        exactLemmasByForm: [:],
        normalizedLemmasByForm: [:],
        normalizedFormEntries: []
    )

    let map: [String: String]
    let formsByLemma: [String: [String]]
    let exactLemmasByForm: [String: [String]]
    let normalizedLemmasByForm: [String: [String]]
    let normalizedFormEntries: [ConjugationFormIndexEntry]

    static func build(from map: [String: String]) -> ConjugationData {
        var formsByLemma: [String: Set<String>] = [:]
        var exactLemmasByForm: [String: Set<String>] = [:]
        var normalizedLemmasByForm: [String: Set<String>] = [:]

        for (form, lemma) in map {
            let exactForm = SearchTextNormalizer.normalizeExact(form)
            let normalizedForm = SearchTextNormalizer.normalize(form)
            let normalizedLemma = SearchTextNormalizer.normalize(lemma)
            guard !exactForm.isEmpty, !normalizedForm.isEmpty, !normalizedLemma.isEmpty else { continue }
            formsByLemma[normalizedLemma, default: []].insert(exactForm)
            exactLemmasByForm[exactForm, default: []].insert(normalizedLemma)
            normalizedLemmasByForm[normalizedForm, default: []].insert(normalizedLemma)
        }

        let normalizedLemmasByFormMap = normalizedLemmasByForm.mapValues { Array($0).sorted() }
        let normalizedFormEntries = normalizedLemmasByFormMap
            .map { ConjugationFormIndexEntry(form: $0.key, lemmas: $0.value) }
            .sorted { $0.form < $1.form }

        return ConjugationData(
            map: map,
            formsByLemma: formsByLemma.mapValues { Array($0).sorted() },
            exactLemmasByForm: exactLemmasByForm.mapValues { Array($0).sorted() },
            normalizedLemmasByForm: normalizedLemmasByFormMap,
            normalizedFormEntries: normalizedFormEntries
        )
    }
}

fileprivate struct SearchIndexedWord: Sendable {
    let word: SimpleWord
    let normalizedWord: String
    let normalizedExamples: String
}

struct WordSearchIndex: Sendable {
    static let empty = WordSearchIndex(
        indexedWords: [],
        exactConjugationLemmasByForm: [:],
        normalizedConjugationLemmasByForm: [:],
        normalizedConjugationFormEntries: [],
        wordsByNormalizedLemma: [:]
    )

    private let indexedWords: [SearchIndexedWord]
    private let exactConjugationLemmasByForm: [String: [String]]
    private let normalizedConjugationLemmasByForm: [String: [String]]
    private let normalizedConjugationFormEntries: [ConjugationFormIndexEntry]
    private let wordsByNormalizedLemma: [String: [SimpleWord]]

    static func build(words: [SimpleWord], conjugationMap: [String: String]) -> WordSearchIndex {
        build(words: words, conjugationData: ConjugationData.build(from: conjugationMap))
    }

    fileprivate static func build(words: [SimpleWord], conjugationData: ConjugationData) -> WordSearchIndex {
        var wordsByNormalizedLemma: [String: [SimpleWord]] = [:]
        var indexedWords: [SearchIndexedWord] = []
        indexedWords.reserveCapacity(words.count)

        for word in words {
            let lemmaSource = word.word.isEmpty ? word.displayWord : word.word
            let normalizedLemma = SearchTextNormalizer.normalize(lemmaSource)
            if !normalizedLemma.isEmpty {
                wordsByNormalizedLemma[normalizedLemma, default: []].append(word)
            }
            indexedWords.append(
                SearchIndexedWord(
                    word: word,
                    normalizedWord: normalizedLemma,
                    normalizedExamples: SearchTextNormalizer.normalize(
                        "\(word.exampleFr) \(word.exampleEn) \(word.exampleZh) \(word.exampleHi)"
                    )
                )
            )
        }

        return WordSearchIndex(
            indexedWords: indexedWords,
            exactConjugationLemmasByForm: conjugationData.exactLemmasByForm,
            normalizedConjugationLemmasByForm: conjugationData.normalizedLemmasByForm,
            normalizedConjugationFormEntries: conjugationData.normalizedFormEntries,
            wordsByNormalizedLemma: wordsByNormalizedLemma
        )
    }

    private func bridgeWords(for query: String) -> [SimpleWord] {
        let exactQuery = SearchTextNormalizer.normalizeExact(query)
        let normalizedQuery = SearchTextNormalizer.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var orderedLemmas: [String] = []
        var seenLemmas: Set<String> = []
        for lemma in (exactConjugationLemmasByForm[exactQuery] ?? []) + (normalizedConjugationLemmasByForm[normalizedQuery] ?? []) {
            if seenLemmas.insert(lemma).inserted {
                orderedLemmas.append(lemma)
            }
        }

        if normalizedQuery.count >= 3 {
            let startIndex = firstConjugationFormEntryIndex(notLessThan: normalizedQuery)
            for entry in normalizedConjugationFormEntries[startIndex...] {
                guard entry.form.hasPrefix(normalizedQuery) else { break }
                guard entry.form != normalizedQuery else { continue }
                for lemma in entry.lemmas where !lemma.hasPrefix(normalizedQuery) && seenLemmas.insert(lemma).inserted {
                    orderedLemmas.append(lemma)
                }
                if orderedLemmas.count >= 8 { break }
            }
        }

        var matchedWords: [SimpleWord] = []
        var seenWordIDs: Set<String> = []
        for lemma in orderedLemmas {
            for word in wordsByNormalizedLemma[lemma] ?? [] where seenWordIDs.insert(word.id).inserted {
                matchedWords.append(word)
            }
        }
        return matchedWords
    }

    func searchResults(for rawQuery: String) -> [SimpleWord] {
        let query = SearchTextNormalizer.normalize(rawQuery)
        guard !query.isEmpty else { return [] }

        var scored: [(word: SimpleWord, score: Int)] = []
        scored.reserveCapacity(indexedWords.count)

        for indexed in indexedWords {
            guard let score = searchScore(for: indexed, query: query) else { continue }
            scored.append((word: indexed.word, score: score))
        }

        var results = scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                if lhs.word.word.count != rhs.word.word.count { return lhs.word.word.count < rhs.word.word.count }
                return lhs.word.word < rhs.word.word
            }
            .map(\.word)

        for bridgeWord in bridgeWords(for: rawQuery).reversed() {
            results.removeAll { $0.id == bridgeWord.id }
            results.insert(bridgeWord, at: 0)
        }

        return results
    }

    private func searchScore(for indexed: SearchIndexedWord, query: String) -> Int? {
        if indexed.normalizedWord == query {
            return 0
        }
        if indexed.normalizedWord.hasPrefix(query) {
            return 1
        }
        if indexed.normalizedWord.contains(query) {
            return 2
        }
        if indexed.normalizedExamples.contains(query) {
            return 5
        }
        return nil
    }

    private func firstConjugationFormEntryIndex(notLessThan query: String) -> Int {
        var low = 0
        var high = normalizedConjugationFormEntries.count
        while low < high {
            let mid = (low + high) / 2
            if normalizedConjugationFormEntries[mid].form < query {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}

fileprivate struct CoreLoadedResources: Sendable {
    let words: [SimpleWord]
    let wordByIdMap: [String: SimpleWord]
    let wordSiblingMap: [String: [String]]
}

fileprivate struct DeferredLoadedResources: Sendable {
    let conjugationData: ConjugationData
    let wordSearchIndex: WordSearchIndex
}

@MainActor
public final class AppState: ObservableObject {
    private static let supportedVoiceIds = Set(TTSVoice.allCases.map(\.rawValue))
    private static let supportedLevels: Set<String> = [
        "All", "A1", "A2", "B1", "B2", "C1", "C2"
    ]

    private enum Keys {
        static let themeMode = "themeMode"
        static let cardFontStyle = "cardFontStyle"
        static let level = "level"
        static let language = "language"
        static let autoPlay = "autoPlay"
        static let spotlightEnabled = "spotlightEnabled"
        static let iCloudSyncEnabled = "iCloudSyncEnabled"
        static let appIconName = "appIconName"
        static let memberUnlocked = "memberUnlocked"
        static let avatarPath = "avatarPath"
        static let selectedVoiceId = "selectedVoiceId"
    }

    @Published public var words: [SimpleWord] = []
    @Published public var spotlightSelectedWordId: String?
    @Published public var widgetSelectedWordId: String?
    @Published public var openMemberPaywallFromDeepLink = false
    @Published public var conjugationFormsByLemma: [String: [String]] = [:]
    @Published var wordSearchIndex: WordSearchIndex = .empty
    @Published public private(set) var hasCompletedInitialResourceLoad: Bool = false
    
    @Published public var themeMode: ThemeMode = .system {
        didSet { saveThemeMode() }
    }
    @Published public var cardFontStyle: CardFontStyle = .sfPro {
        didSet { saveCardFontStyle() }
    }
    @Published public var level: String = "All" {
        didSet {
            let canonical = Self.canonicalLevel(level)
            if canonical != level {
                level = canonical
                return
            }
            saveLevel()
        }
    }
    @Published public var language: String = "en" {
        didSet { saveLanguage() }
    }
    @Published public var autoPlay: Bool = false {
        didSet { saveAutoPlay() }
    }
    @Published public var spotlightEnabled: Bool = false {
        didSet { saveSpotlightEnabled() }
    }
    @Published public var iCloudSyncEnabled: Bool = false {
        didSet { saveICloudSyncEnabled() }
    }
    @Published public var appIconName: String? = nil {
        didSet { saveAppIconName() }
    }
    @Published public var memberUnlocked: Bool = false {
        didSet { saveMemberUnlocked() }
    }
    @Published public var avatarPath: String = "" {
        didSet { saveAvatarPath() }
    }
    @Published public var selectedVoiceId: String = TTSVoice.default.rawValue {
        didSet {
            if !Self.supportedVoiceIds.contains(selectedVoiceId) {
                if selectedVoiceId != TTSVoice.default.rawValue {
                    selectedVoiceId = TTSVoice.default.rawValue
                }
                return
            }
            saveSelectedVoiceId()
            AudioCacheManager.shared.clearCache()
        }
    }
    
    private var wordByIdMap: [String: SimpleWord] = [:]
    private var wordSiblingMap: [String: [String]] = [:]
    private var conjugationData: ConjugationData = .empty
    private var pendingSpotlightIndexTask: Task<Void, Never>? = nil
    
    private let userDefaults = UserDefaults.standard
    private let fallbackWords: [SimpleWord] = [
        SimpleWord(
            id: "w_bonjour",
            word: "bonjour",
            tag: "INTJ",
            level: "A1",
            translationZh: "你好",
            translationEn: "hello",
            exampleFr: "Bonjour, comment ca va ?",
            exampleZh: "你好，你最近怎么样？"
        ),
        SimpleWord(
            id: "w_merci",
            word: "merci",
            tag: "INTJ",
            level: "A1",
            translationZh: "谢谢",
            translationEn: "thank you",
            exampleFr: "Merci pour ton aide.",
            exampleZh: "谢谢你的帮助。"
        ),
        SimpleWord(
            id: "w_maison",
            word: "maison",
            tag: "N",
            level: "A1",
            translationZh: "房子；家",
            translationEn: "house; home",
            exampleFr: "Je rentre a la maison.",
            exampleZh: "我要回家了。"
        ),
        SimpleWord(
            id: "w_cafe",
            word: "cafe",
            tag: "N",
            level: "A1",
            translationZh: "咖啡；咖啡馆",
            translationEn: "coffee; cafe",
            exampleFr: "Je prends un cafe au cafe du coin.",
            exampleZh: "我在街角的咖啡馆喝咖啡。"
        )
    ]
    
    public init() {
        loadUserPreferences()
        words = fallbackWords
        buildWordLinks(words)
        rebuildSearchIndex()

        let bundlePath = resourceBundlePath
        Task { [bundlePath, fallbackWords = fallbackWords] in
            let coreResources = await Self.loadCoreResources(bundlePath: bundlePath, fallbackWords: fallbackWords)
            applyLoadedCoreResources(coreResources)
            conjugationData = .empty
            conjugationFormsByLemma = [:]
            rebuildSearchIndex()
            hasCompletedInitialResourceLoad = true

            let deferredResources = await Self.loadDeferredResources(
                bundlePath: bundlePath,
                words: coreResources.words
            )
            applyDeferredResources(deferredResources)
            if spotlightEnabled {
                scheduleSpotlightIndexing(
                    words: coreResources.words,
                    conjugationFormsByLemma: deferredResources.conjugationData.formsByLemma
                )
            }
        }
    }

    // MARK: - Language Helpers

    public enum AppLanguage: String {
        case en
        case zh
        case hi
    }

    public var currentLanguage: AppLanguage {
        AppLanguage(rawValue: language) ?? .en
    }

    public func localized(_ en: String, _ zh: String, _ hi: String) -> String {
        switch currentLanguage {
        case .en: return en
        case .zh: return zh
        case .hi: return hi
        }
    }

    public func translationText(for word: SimpleWord) -> String {
        let en = word.translationEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let zh = word.translationZh.trimmingCharacters(in: .whitespacesAndNewlines)
        let hi = word.translationHi.trimmingCharacters(in: .whitespacesAndNewlines)
        switch currentLanguage {
        case .en: return en.isEmpty ? (zh.isEmpty ? hi : zh) : en
        case .zh: return zh.isEmpty ? (en.isEmpty ? hi : en) : zh
        case .hi: return hi.isEmpty ? (en.isEmpty ? zh : en) : hi
        }
    }

    public func translatedExampleText(for word: SimpleWord) -> String {
        let en = word.exampleEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let zh = word.exampleZh.trimmingCharacters(in: .whitespacesAndNewlines)
        let hi = word.exampleHi.trimmingCharacters(in: .whitespacesAndNewlines)
        switch currentLanguage {
        case .en: return en
        case .zh: return zh
        case .hi: return hi
        }
    }
    
    // MARK: - User Preferences Loading
    
    private func loadUserPreferences() {
        // Theme Mode
        if let rawValue = userDefaults.value(forKey: Keys.themeMode) as? Int {
            if let mode = ThemeMode(rawValue: rawValue) {
                themeMode = mode
            } else if rawValue == 1 {
                themeMode = .light
                userDefaults.set(ThemeMode.light.rawValue, forKey: Keys.themeMode)
            } else {
                themeMode = .system
                userDefaults.set(ThemeMode.system.rawValue, forKey: Keys.themeMode)
            }
        }

        if let savedCardFontStyle = userDefaults.string(forKey: Keys.cardFontStyle),
           let style = CardFontStyle(rawValue: savedCardFontStyle) {
            cardFontStyle = style
        }
        
        // Level
        if let savedLevel = userDefaults.string(forKey: Keys.level) {
            level = Self.canonicalLevel(savedLevel)
        }
        
        // Language
        if let savedLanguage = userDefaults.string(forKey: Keys.language) {
            language = savedLanguage
        }
        
        // Auto Play
        autoPlay = userDefaults.bool(forKey: Keys.autoPlay)
        
        // Spotlight Enabled
        spotlightEnabled = userDefaults.bool(forKey: Keys.spotlightEnabled)

        // iCloud Sync Enabled
        iCloudSyncEnabled = userDefaults.bool(forKey: Keys.iCloudSyncEnabled)
        
        // App Icon Name
        appIconName = userDefaults.string(forKey: Keys.appIconName)
        
        // Member Unlocked
        memberUnlocked = userDefaults.bool(forKey: Keys.memberUnlocked)
        WidgetDataService.writeMemberUnlocked(memberUnlocked)
        
        // Avatar Path
        if let savedAvatarPath = userDefaults.string(forKey: Keys.avatarPath) {
            avatarPath = savedAvatarPath
        }
        if let savedVoiceId = userDefaults.string(forKey: Keys.selectedVoiceId) {
            selectedVoiceId = savedVoiceId
        }
    }
    
    // MARK: - User Preferences Saving
    
    private func saveThemeMode() {
        userDefaults.set(themeMode.rawValue, forKey: Keys.themeMode)
    }

    private func saveCardFontStyle() {
        userDefaults.set(cardFontStyle.rawValue, forKey: Keys.cardFontStyle)
    }
    
    private func saveLevel() {
        userDefaults.set(level, forKey: Keys.level)
    }

    private static func canonicalLevel(_ rawLevel: String) -> String {
        let trimmed = rawLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "All" }

        if trimmed == "全部" || trimmed == "सभी" {
            return "All"
        }

        let upper = trimmed.uppercased()
        if upper == "ALL" {
            return "All"
        }
        if supportedLevels.contains(upper) {
            return upper
        }
        if supportedLevels.contains(trimmed) {
            return trimmed
        }
        return "All"
    }
    
    private func saveLanguage() {
        userDefaults.set(language, forKey: Keys.language)
    }
    
    private func saveAutoPlay() {
        userDefaults.set(autoPlay, forKey: Keys.autoPlay)
    }
    
    private func saveSpotlightEnabled() {
        userDefaults.set(spotlightEnabled, forKey: Keys.spotlightEnabled)
    }

    private func saveICloudSyncEnabled() {
        userDefaults.set(iCloudSyncEnabled, forKey: Keys.iCloudSyncEnabled)
    }
    
    private func saveAppIconName() {
        if let iconName = appIconName {
            userDefaults.set(iconName, forKey: Keys.appIconName)
        } else {
            userDefaults.removeObject(forKey: Keys.appIconName)
        }
    }
    
    private func saveMemberUnlocked() {
        userDefaults.set(memberUnlocked, forKey: Keys.memberUnlocked)
        WidgetDataService.writeMemberUnlocked(memberUnlocked)
    }
    
    private func saveAvatarPath() {
        userDefaults.set(avatarPath, forKey: Keys.avatarPath)
    }
    
    private func saveSelectedVoiceId() {
        userDefaults.set(selectedVoiceId, forKey: Keys.selectedVoiceId)
    }
    
    // MARK: - Data Loading
    
    private func applyLoadedCoreResources(_ resources: CoreLoadedResources) {
        words = resources.words
        wordByIdMap = resources.wordByIdMap
        wordSiblingMap = resources.wordSiblingMap
    }

    private func applyDeferredResources(_ resources: DeferredLoadedResources) {
        conjugationData = resources.conjugationData
        conjugationFormsByLemma = resources.conjugationData.formsByLemma
        wordSearchIndex = resources.wordSearchIndex
    }

    private func rebuildSearchIndex() {
        wordSearchIndex = WordSearchIndex.build(words: words, conjugationData: conjugationData)
    }

    nonisolated private static func loadCoreResources(bundlePath: String, fallbackWords: [SimpleWord]) async -> CoreLoadedResources {
        await Task.detached(priority: .userInitiated) {
            let preferredSources = ["Croisssante-Words", "words"]
            let words = preferredSources
                .compactMap { loadJSONResource($0, as: [SimpleWord].self, bundlePath: bundlePath) }
                .first ?? fallbackWords
            let wordLinks = buildWordLinks(words)
            return CoreLoadedResources(
                words: words,
                wordByIdMap: wordLinks.byIdMap,
                wordSiblingMap: wordLinks.siblingMap
            )
        }.value
    }

    nonisolated private static func loadDeferredResources(
        bundlePath: String,
        words: [SimpleWord]
    ) async -> DeferredLoadedResources {
        await Task.detached(priority: .utility) {
            let conjugationMap = loadJSONResource("conjugation", as: [String: String].self, bundlePath: bundlePath) ?? [:]
            let conjugationData = ConjugationData.build(from: conjugationMap)
            return DeferredLoadedResources(
                conjugationData: conjugationData,
                wordSearchIndex: WordSearchIndex.build(words: words, conjugationData: conjugationData)
            )
        }.value
    }

    nonisolated private static func loadJSONResource<T: Decodable & Sendable>(_ name: String, as type: T.Type, bundlePath: String) -> T? {
        let bundle = Bundle(path: bundlePath) ?? .main
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private var resourceBundlePath: String {
        #if SWIFT_PACKAGE
        return Bundle.module.bundlePath
        #else
        return Bundle.main.bundlePath
        #endif
    }
    
    // MARK: - Word Management
    
    private func buildWordLinks(_ words: [SimpleWord]) {
        let links = Self.buildWordLinks(words)
        wordSiblingMap = links.siblingMap
        wordByIdMap = links.byIdMap
    }
    
    public func getWordById(_ id: String) -> SimpleWord? {
        return wordByIdMap[id]
    }

    public func getAllSenses(_ word: SimpleWord) -> [SimpleWord] {
        let key = normalizeText(word.word.isEmpty ? word.displayWord : word.word)
        let ids = wordSiblingMap[key] ?? []
        return ids
            .compactMap { wordByIdMap[$0] }
            .sorted { lhs, rhs in
                if lhs.senseIndex != rhs.senseIndex {
                    return lhs.senseIndex < rhs.senseIndex
                }
                return lhs.id < rhs.id
            }
    }
    
    public func getSiblings(_ word: SimpleWord) -> [SimpleWord] {
        getAllSenses(word).filter { $0.id != word.id }
    }
    
    public func hasMultipleEntries(_ word: SimpleWord) -> Bool {
        getAllSenses(word).count > 1
    }
    
    public func isPolysemous(_ word: SimpleWord?) -> Bool {
        guard let word = word else { return false }
        return hasMultipleEntries(word)
    }

    private func normalizeText(_ text: String) -> String {
        SearchTextNormalizer.normalize(text)
    }

    nonisolated private static func buildWordLinks(_ words: [SimpleWord]) -> (siblingMap: [String: [String]], byIdMap: [String: SimpleWord]) {
        var siblingMap: [String: [String]] = [:]
        var byIdMap: [String: SimpleWord] = [:]

        for word in words {
            let key = SearchTextNormalizer.normalize(word.word.isEmpty ? word.displayWord : word.word)
            if !key.isEmpty {
                siblingMap[key, default: []].append(word.id)
            }
            byIdMap[word.id] = word
        }

        return (siblingMap, byIdMap)
    }

    private func scheduleSpotlightIndexing(words: [SimpleWord], conjugationFormsByLemma: [String: [String]]) {
        pendingSpotlightIndexTask?.cancel()
        pendingSpotlightIndexTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, spotlightEnabled else { return }
            SpotlightService.shared.indexAllWords(words, conjugationFormsByLemma: conjugationFormsByLemma)
        }
    }
}
