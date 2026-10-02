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
                        "\(word.exampleFr) \(word.exampleEn) \(word.exampleZh)"
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

struct UserWordLocalizedContent: Equatable, Sendable {
    var translation: String
    var frenchExample: String
    var example: String
}

struct LibrarySyncPayload: Codable {
    var words: [SimpleWord]
    var favoriteWordIds: [String]
    var dailyLookupCounts: [String: Int]
    var updatedAt: Date
}

@MainActor
public final class AppState: ObservableObject {
    private static let supportedVoiceIds = Set(TTSVoice.allCases.map(\.rawValue))

    private enum Keys {
        static let themeMode = "themeMode"
        static let cardFontStyle = "cardFontStyle"
        static let language = "language"
        static let autoPlay = "autoPlay"
        static let iCloudSyncEnabled = "iCloudSyncEnabled"
        static let appIconName = "appIconName"
        static let avatarPath = "avatarPath"
        static let selectedVoiceId = "selectedVoiceId"
        static let dailyLookupCounts = "daily_lookup_counts_v1"
        static let libraryUpdatedAt = "library_updated_at_v1"
    }

    @Published public private(set) var words: [SimpleWord] = []
    @Published public private(set) var dailyLookupCounts: [String: Int] = [:]
    @Published public var conjugationFormsByLemma: [String: [String]] = [:]
    @Published var wordSearchIndex: WordSearchIndex = .empty
    @Published public private(set) var hasCompletedInitialResourceLoad: Bool = false

    @Published public var themeMode: ThemeMode = .system {
        didSet { userDefaults.set(themeMode.rawValue, forKey: Keys.themeMode) }
    }
    @Published public var cardFontStyle: CardFontStyle = .sfPro {
        didSet { userDefaults.set(cardFontStyle.rawValue, forKey: Keys.cardFontStyle) }
    }
    @Published public var language: String = "en" {
        didSet {
            if language != "en" && language != "zh" {
                language = "en"
                return
            }
            userDefaults.set(language, forKey: Keys.language)
        }
    }
    @Published public var autoPlay: Bool = false {
        didSet { userDefaults.set(autoPlay, forKey: Keys.autoPlay) }
    }
    @Published public var iCloudSyncEnabled: Bool = false {
        didSet {
            let applied = ICloudSyncService.shared.setEnabled(iCloudSyncEnabled)
            if applied != iCloudSyncEnabled {
                iCloudSyncEnabled = applied
            }
            userDefaults.set(iCloudSyncEnabled, forKey: Keys.iCloudSyncEnabled)
            if iCloudSyncEnabled { requestICloudPush() }
        }
    }
    @Published public var appIconName: String? = nil {
        didSet {
            if let appIconName {
                userDefaults.set(appIconName, forKey: Keys.appIconName)
            } else {
                userDefaults.removeObject(forKey: Keys.appIconName)
            }
        }
    }
    @Published public var avatarPath: String = "" {
        didSet { userDefaults.set(avatarPath, forKey: Keys.avatarPath) }
    }
    @Published public var selectedVoiceId: String = TTSVoice.default.rawValue {
        didSet {
            if !Self.supportedVoiceIds.contains(selectedVoiceId) {
                if selectedVoiceId != TTSVoice.default.rawValue {
                    selectedVoiceId = TTSVoice.default.rawValue
                }
                return
            }
            userDefaults.set(selectedVoiceId, forKey: Keys.selectedVoiceId)
            AudioCacheManager.shared.clearCache()
        }
    }

    private var wordByIdMap: [String: SimpleWord] = [:]
    private var conjugationData: ConjugationData = .empty
    private var libraryUpdatedAt: Date = .distantPast
    private var favoriteWordIdsForSync: (() -> [String])?
    private var applyFavoriteWordIdsFromSync: (([String]) -> Void)?
    private let userDefaults = UserDefaults.standard

    private static let libraryFileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Croissante", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("user_words.json")
    }()

    public init() {
        loadUserPreferences()
        loadLibrary()
        rebuildDerivedState()
        hasCompletedInitialResourceLoad = true

        let bundlePath = resourceBundlePath
        Task {
            let data = await Self.loadConjugation(bundlePath: bundlePath)
            conjugationData = data
            conjugationFormsByLemma = data.formsByLemma
            rebuildSearchIndex()
        }
    }

    // MARK: - Language

    public enum AppLanguage: String {
        case en
        case zh
    }

    public var currentLanguage: AppLanguage {
        AppLanguage(rawValue: language) ?? .en
    }

    public func localized(_ en: String, _ zh: String) -> String {
        currentLanguage == .zh ? zh : en
    }

    public func translationText(for word: SimpleWord) -> String {
        let zh = word.translationZh.trimmingCharacters(in: .whitespacesAndNewlines)
        let en = word.translationEn.trimmingCharacters(in: .whitespacesAndNewlines)
        switch currentLanguage {
        case .en: return en.isEmpty ? zh : en
        case .zh: return zh.isEmpty ? en : zh
        }
    }

    public func translatedExampleText(for word: SimpleWord) -> String {
        switch currentLanguage {
        case .en: return word.exampleEn.trimmingCharacters(in: .whitespacesAndNewlines)
        case .zh: return word.exampleZh.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public func frenchExampleText(for word: SimpleWord) -> String {
        word.exampleFr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func editableLocalizedContent(for word: SimpleWord) -> UserWordLocalizedContent {
        UserWordLocalizedContent(
            translation: currentLanguage == .zh ? word.translationZh : word.translationEn,
            frenchExample: word.exampleFr,
            example: translatedExampleText(for: word)
        )
    }

    func saveLocalizedContent(_ content: UserWordLocalizedContent, for word: SimpleWord) {
        var updated = word
        updated.exampleFr = content.frenchExample.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = content.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        let example = content.example.trimmingCharacters(in: .whitespacesAndNewlines)
        switch currentLanguage {
        case .en:
            updated.translationEn = translation
            updated.exampleEn = example
        case .zh:
            updated.translationZh = translation
            updated.exampleZh = example
        }
        guard updated != word else { return }
        updateWord(updated)
    }

    // MARK: - Library

    @discardableResult
    public func addWord(form rawForm: String) -> SimpleWord? {
        let form = rawForm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !form.isEmpty else { return nil }

        let normalized = SearchTextNormalizer.normalize(form)
        if let existing = words.first(where: { SearchTextNormalizer.normalize($0.word) == normalized }) {
            recordLookup(wordId: existing.id)
            return existing
        }

        let word = SimpleWord(id: SimpleWord.makeID(for: form), word: form)
        words.insert(word, at: 0)
        incrementTodayLookupCount()
        commitLibraryChange()
        return word
    }

    public func updateWord(_ word: SimpleWord) {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[index] = word
        commitLibraryChange()
    }

    public func recordLookup(wordId: String) {
        guard let index = words.firstIndex(where: { $0.id == wordId }) else { return }
        let word = words.remove(at: index)
        words.insert(word, at: 0)
        incrementTodayLookupCount()
        commitLibraryChange()
    }

    public func removeWord(id: String) {
        guard words.contains(where: { $0.id == id }) else { return }
        words.removeAll { $0.id == id }
        commitLibraryChange()
    }

    public func resetLibrary() {
        words = []
        dailyLookupCounts = [:]
        commitLibraryChange()
    }

    public func lookupCount(for date: Date) -> Int {
        dailyLookupCounts[Self.dayKey(for: date)] ?? 0
    }

    public func getWordById(_ id: String) -> SimpleWord? {
        wordByIdMap[id]
    }

    private func incrementTodayLookupCount() {
        let key = Self.dayKey(for: Date())
        dailyLookupCounts[key, default: 0] += 1
        pruneLookupCounts()
    }

    private func pruneLookupCounts() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -400, to: Date()) ?? .distantPast
        let cutoffKey = Self.dayKey(for: cutoff)
        dailyLookupCounts = dailyLookupCounts.filter { $0.key >= cutoffKey }
    }

    private func commitLibraryChange() {
        libraryUpdatedAt = Date()
        rebuildDerivedState()
        saveLibrary()
        requestICloudPush()
    }

    private func rebuildDerivedState() {
        wordByIdMap = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        rebuildSearchIndex()
    }

    private func rebuildSearchIndex() {
        wordSearchIndex = WordSearchIndex.build(words: words, conjugationData: conjugationData)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dayKey(for date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }

    // MARK: - Persistence

    private func loadUserPreferences() {
        if let rawValue = userDefaults.value(forKey: Keys.themeMode) as? Int,
           let mode = ThemeMode(rawValue: rawValue) {
            themeMode = mode
        }
        if let saved = userDefaults.string(forKey: Keys.cardFontStyle), let style = CardFontStyle(rawValue: saved) {
            cardFontStyle = style
        }
        if let saved = userDefaults.string(forKey: Keys.language) {
            language = saved
        }
        autoPlay = userDefaults.bool(forKey: Keys.autoPlay)
        var savedICloudSync = userDefaults.bool(forKey: Keys.iCloudSyncEnabled)
        if savedICloudSync && !ICloudSyncService.isAccountAvailable {
            savedICloudSync = false
            userDefaults.set(false, forKey: Keys.iCloudSyncEnabled)
        }
        iCloudSyncEnabled = savedICloudSync
        appIconName = userDefaults.string(forKey: Keys.appIconName)
        if let saved = userDefaults.string(forKey: Keys.avatarPath) {
            avatarPath = saved
        }
        if let saved = userDefaults.string(forKey: Keys.selectedVoiceId) {
            selectedVoiceId = saved
        }
        if let counts = userDefaults.dictionary(forKey: Keys.dailyLookupCounts) as? [String: Int] {
            dailyLookupCounts = counts
        }
        libraryUpdatedAt = userDefaults.object(forKey: Keys.libraryUpdatedAt) as? Date ?? .distantPast
    }

    private func loadLibrary() {
        guard let data = try? Data(contentsOf: Self.libraryFileURL),
              let decoded = try? Self.makeDecoder().decode([SimpleWord].self, from: data) else {
            words = []
            return
        }
        words = decoded
    }

    private func saveLibrary() {
        userDefaults.set(dailyLookupCounts, forKey: Keys.dailyLookupCounts)
        userDefaults.set(libraryUpdatedAt, forKey: Keys.libraryUpdatedAt)
        let snapshot = words
        let url = Self.libraryFileURL
        Task.detached(priority: .utility) {
            guard let data = try? Self.makeEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    nonisolated private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    nonisolated private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - iCloud

    func configureICloudSync(
        favoriteWordIdsForSync: @escaping () -> [String],
        applyFavoriteWordIdsFromSync: @escaping ([String]) -> Void
    ) {
        self.favoriteWordIdsForSync = favoriteWordIdsForSync
        self.applyFavoriteWordIdsFromSync = applyFavoriteWordIdsFromSync
        ICloudSyncService.shared.configure(isEnabled: iCloudSyncEnabled) { [weak self] data in
            self?.applyRemotePayload(data)
        }
    }

    func requestICloudPush() {
        guard iCloudSyncEnabled, ICloudSyncService.isAccountAvailable, hasCompletedInitialResourceLoad else { return }
        let payload = LibrarySyncPayload(
            words: words,
            favoriteWordIds: favoriteWordIdsForSync?() ?? [],
            dailyLookupCounts: dailyLookupCounts,
            updatedAt: libraryUpdatedAt
        )
        guard let data = try? Self.makeEncoder().encode(payload) else { return }
        ICloudSyncService.shared.push(payload: data)
    }

    private func applyRemotePayload(_ data: Data) {
        guard let payload = try? Self.makeDecoder().decode(LibrarySyncPayload.self, from: data) else { return }
        guard payload.updatedAt > libraryUpdatedAt else { return }

        var merged = payload.words
        let remoteIds = Set(merged.map(\.id))
        merged.append(contentsOf: words.filter { !remoteIds.contains($0.id) })
        words = merged
        dailyLookupCounts = dailyLookupCounts.merging(payload.dailyLookupCounts) { max($0, $1) }
        libraryUpdatedAt = payload.updatedAt
        rebuildDerivedState()
        saveLibrary()
        applyFavoriteWordIdsFromSync?(payload.favoriteWordIds)
    }

    // MARK: - Helpers

    nonisolated private static func loadConjugation(bundlePath: String) async -> ConjugationData {
        await Task.detached(priority: .utility) {
            let bundle = Bundle(path: bundlePath) ?? .main
            guard let url = bundle.url(forResource: "conjugation", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let map = try? JSONDecoder().decode([String: String].self, from: data) else {
                return ConjugationData.empty
            }
            return ConjugationData.build(from: map)
        }.value
    }

    private var resourceBundlePath: String {
        #if SWIFT_PACKAGE
        return Bundle.module.bundlePath
        #else
        return Bundle.main.bundlePath
        #endif
    }
}
