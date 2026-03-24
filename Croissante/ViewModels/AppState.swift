import SwiftUI

public enum ThemeMode: Int, Codable {
    case system = 0
    case light = 1
    case dark = 2
    case paper = 3
    case graphite = 4
}

@MainActor
public final class AppState: ObservableObject {
    private enum Keys {
        static let themeMode = "themeMode"
        static let level = "level"
        static let language = "language"
        static let autoPlay = "autoPlay"
        static let spotlightEnabled = "spotlightEnabled"
        static let iCloudSyncEnabled = "iCloudSyncEnabled"
        static let appIconName = "appIconName"
        static let memberUnlocked = "memberUnlocked"
        static let avatarPath = "avatarPath"
        static let masteredWords = "masteredWords"
        static let learningQueueIds = "learningQueueIds"
        static let selectedVoiceId = "selectedVoiceId"
    }

    @Published public var words: [SimpleWord] = []
    @Published public var spotlightSelectedWordId: String?
    @Published public var conjugationMap: [String: String] = [:]
    @Published public var conjugationFormsByLemma: [String: [String]] = [:]
    
    @Published public var themeMode: ThemeMode = .system {
        didSet { saveThemeMode() }
    }
    @Published public var level: String = "All" {
        didSet { saveLevel() }
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
    @Published public var selectedVoiceId: String = "oziFLKtaxVDHQAh7o45V" {
        didSet {
            saveSelectedVoiceId()
            AudioCacheManager.shared.clearCache()
        }
    }
    
    @Published public var masteredWords: Set<String> = [] {
        didSet { saveMasteredWords() }
    }
    @Published public var learningQueueIds: Set<String> = []
    
    @Published public var searchQuery: String = ""
    @Published public var searchResults: [SimpleWord] = []
    
    private var wordByIdMap: [String: SimpleWord] = [:]
    private var wordSiblingMap: [String: [String]] = [:]
    private var normalizedConjugationMap: [String: String] = [:]
    
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
        loadWords()
        loadConjugationData()
        if spotlightEnabled {
            SpotlightService.shared.indexAllWords(words, conjugationFormsByLemma: conjugationFormsByLemma, spotlightEnabled: true)
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
        if let rawValue = userDefaults.value(forKey: Keys.themeMode) as? Int,
           let mode = ThemeMode(rawValue: rawValue) {
            themeMode = mode
        }
        
        // Level
        if let savedLevel = userDefaults.string(forKey: Keys.level) {
            level = savedLevel
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
        
        // Avatar Path
        if let savedAvatarPath = userDefaults.string(forKey: Keys.avatarPath) {
            avatarPath = savedAvatarPath
        }
        if let savedVoiceId = userDefaults.string(forKey: Keys.selectedVoiceId) {
            selectedVoiceId = savedVoiceId
        }
        
        // Mastered Words
        if let masteredWordsArray = userDefaults.stringArray(forKey: Keys.masteredWords) {
            masteredWords = Set(masteredWordsArray)
        }
        
        // Learning Queue (optional)
        if let learningQueueArray = userDefaults.stringArray(forKey: Keys.learningQueueIds) {
            learningQueueIds = Set(learningQueueArray)
        }
    }
    
    // MARK: - User Preferences Saving
    
    private func saveThemeMode() {
        userDefaults.set(themeMode.rawValue, forKey: Keys.themeMode)
    }
    
    private func saveLevel() {
        userDefaults.set(level, forKey: Keys.level)
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
    }
    
    private func saveAvatarPath() {
        userDefaults.set(avatarPath, forKey: Keys.avatarPath)
    }
    
    private func saveSelectedVoiceId() {
        userDefaults.set(selectedVoiceId, forKey: Keys.selectedVoiceId)
    }
    
    private func saveMasteredWords() {
        userDefaults.set(Array(masteredWords), forKey: Keys.masteredWords)
    }
    
    private func saveLearningQueue() {
        userDefaults.set(Array(learningQueueIds), forKey: Keys.learningQueueIds)
    }
    
    // MARK: - Data Loading
    
    private func loadWords() {
        let preferredSources = ["words_test_500", "words"]
        words = preferredSources
            .compactMap { loadJSONResource($0, as: [SimpleWord].self) }
            .first ?? fallbackWords
        buildWordLinks(words)
    }
    
    private func loadConjugationData() {
        conjugationMap = loadJSONResource("conjugation", as: [String: String].self) ?? [:]

        var formsByLemma: [String: Set<String>] = [:]
        var normalizedMap: [String: String] = [:]
        for (form, lemma) in conjugationMap {
            let normalizedLemma = normalizeText(lemma)
            let normalizedForm = normalizeText(form)
            guard !normalizedLemma.isEmpty, !normalizedForm.isEmpty else { continue }
            formsByLemma[normalizedLemma, default: []].insert(normalizedForm)
            normalizedMap[normalizedForm] = normalizedLemma
        }
        conjugationFormsByLemma = formsByLemma.mapValues { Array($0).sorted() }
        normalizedConjugationMap = normalizedMap
    }

    private func loadJSONResource<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let url = resourceBundle.url(forResource: name, withExtension: "json") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
    
    // MARK: - Word Management
    
    private func buildWordLinks(_ words: [SimpleWord]) {
        var siblingMap: [String: [String]] = [:]
        var byIdMap: [String: SimpleWord] = [:]
        
        for word in words {
            let key = normalizeText(word.word.isEmpty ? word.displayWord : word.word)
            if !key.isEmpty {
                siblingMap[key, default: []].append(word.id)
            }
            byIdMap[word.id] = word
        }
        
        wordSiblingMap = siblingMap
        wordByIdMap = byIdMap
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
    
    // MARK: - Learning Functions
    
    public func markWordMastered(_ wordId: String) {
        masteredWords.insert(wordId)
    }
    
    public func unmarkWordMastered(_ wordId: String) {
        masteredWords.remove(wordId)
    }
    
    public func isWordMastered(_ wordId: String) -> Bool {
        return masteredWords.contains(wordId)
    }
    
    public func updateLearningQueue(_ wordIds: [String]) {
        learningQueueIds = Set(wordIds)
        saveLearningQueue()
    }
    
    public func getLearningQueueWords() -> [SimpleWord] {
        return learningQueueIds.compactMap { getWordById($0) }
    }
    
    public func getMasteredWords() -> [SimpleWord] {
        return masteredWords.compactMap { getWordById($0) }
    }
    
    // MARK: - Clear User State
    
    public func clearUserState() {
        themeMode = .system
        level = "All"
        language = "en"
        autoPlay = false
        spotlightEnabled = false
        iCloudSyncEnabled = false
        appIconName = nil
        memberUnlocked = false
        avatarPath = ""
        masteredWords = []
        learningQueueIds = []
        searchQuery = ""
        searchResults = []
        
        // Clear all user defaults
        if let domain = Bundle.main.bundleIdentifier {
            userDefaults.removePersistentDomain(forName: domain)
        } else {
            [
                Keys.themeMode,
                Keys.level,
                Keys.language,
                Keys.autoPlay,
                Keys.spotlightEnabled,
                Keys.iCloudSyncEnabled,
                Keys.appIconName,
                Keys.memberUnlocked,
                Keys.avatarPath,
                Keys.masteredWords,
                Keys.learningQueueIds
            ].forEach { userDefaults.removeObject(forKey: $0) }
        }
    }
    
    // MARK: - Search Functions
    
    public func searchWords(query: String) -> [SimpleWord] {
        let normalizedQuery = normalizeText(query)
        if normalizedQuery.isEmpty {
            searchResults = []
            return []
        }

        let conjugatedLemma = normalizedConjugationMap[normalizedQuery] ?? ""
        
        let results = words.filter { word in
            let normalizedWord = normalizeText(word.word)
            let normalizedDisplayWord = normalizeText(word.displayWord)
            return normalizedWord.contains(normalizedQuery) ||
                normalizedDisplayWord.contains(normalizedQuery) ||
                normalizeText(word.translationEn).contains(normalizedQuery) ||
                normalizeText(word.translationZh).contains(normalizedQuery) ||
                normalizeText(word.translationHi).contains(normalizedQuery) ||
                (!conjugatedLemma.isEmpty && conjugatedLemma == normalizedWord)
        }
        
        searchResults = results
        return results
    }

    private func normalizeText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
