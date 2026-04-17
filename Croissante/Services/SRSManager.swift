import Foundation
import Combine

private struct SRSScheduler {
    let calendar: Calendar
    let newCardQuotaRatio: Double
    let retryIntervalDays: Int

    func normalizedReviewDate(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func retryReviewDate(from date: Date) -> Date {
        dateByAddingDays(retryIntervalDays, from: date)
    }

    /// 单纯按间隔天数推算下次复习日，不再有毕业概念。
    func scheduledReviewDate(forInterval intervalDays: Int, from date: Date) -> Date {
        let anchor = normalizedReviewDate(date)
        guard intervalDays > 0 else { return dateByAddingDays(1, from: anchor) }
        return dateByAddingDays(intervalDays, from: anchor)
    }

    /// 右滑掌握后的下一档间隔。
    /// 软梯度：0 → 1 → 2 → 4 → 8 → 15 → 30，此后每次正确再 ×2（60、120、240…）。
    /// 用户学得越稳，卡片出现得越稀疏，但永远留在系统里。
    func nextMasteryInterval(from current: Int) -> Int {
        let ladder = SRSRules.masteryLadder
        if let nextStep = ladder.first(where: { current < $0 }) {
            return nextStep
        }

        let highestStep = ladder.last ?? 1
        return max(current * 2, highestStep * 2)
    }

    func buildDailyDeck(
        from levelFilteredWords: [SimpleWord],
        records: [String: LearningRecord],
        now: Date,
        deckLimit: Int
    ) -> [SimpleWord] {
        let dueReviewWords = dueReviewWords(in: levelFilteredWords, records: records, now: now)
        let newWords = levelFilteredWords.filter { records[$0.id] == nil }.shuffled()

        let guaranteedNewQuota = dailyNewWordQuota(for: deckLimit)
        let reviewQuota = max(0, deckLimit - guaranteedNewQuota)

        var selectedReviewWords = Array(dueReviewWords.prefix(reviewQuota))
        var selectedNewWords = Array(newWords.prefix(guaranteedNewQuota))

        if selectedReviewWords.count < reviewQuota {
            let shortage = reviewQuota - selectedReviewWords.count
            let remainingNewWords = newWords.dropFirst(selectedNewWords.count)
            selectedNewWords.append(contentsOf: remainingNewWords.prefix(shortage))
        }

        if selectedNewWords.count < guaranteedNewQuota {
            let shortage = guaranteedNewQuota - selectedNewWords.count
            let remainingReviewWords = dueReviewWords.dropFirst(selectedReviewWords.count)
            selectedReviewWords.append(contentsOf: remainingReviewWords.prefix(shortage))
        }

        return Array((selectedReviewWords + selectedNewWords).shuffled().prefix(deckLimit))
    }

    func buildInfinitePracticeBatch(
        from levelFilteredWords: [SimpleWord],
        records: [String: LearningRecord],
        now: Date,
        batchSize: Int
    ) -> [SimpleWord] {
        guard batchSize > 0, !levelFilteredWords.isEmpty else { return [] }

        let dueReviewWords = dueReviewWords(in: levelFilteredWords, records: records, now: now)
        let newWords = levelFilteredWords.filter { records[$0.id] == nil }.shuffled()
        let reinforcementWords = levelFilteredWords.filter { records[$0.id] != nil }.shuffled()

        var result: [SimpleWord] = []
        var seenIds: Set<String> = []

        func appendUnique(_ words: [SimpleWord]) {
            for word in words {
                guard seenIds.insert(word.id).inserted else { continue }
                result.append(word)
                if result.count >= batchSize { return }
            }
        }

        appendUnique(dueReviewWords)
        if result.count < batchSize { appendUnique(newWords) }
        if result.count < batchSize { appendUnique(reinforcementWords) }
        if result.count < batchSize { appendUnique(levelFilteredWords.shuffled()) }

        return Array(result.prefix(batchSize))
    }

    func buildPreviewContinuation(
        from filteredWords: [SimpleWord],
        records: [String: LearningRecord],
        now: Date,
        excluding excludedIds: Set<String>,
        dayKey: String
    ) -> [SimpleWord] {
        let availableWords = filteredWords.filter { !excludedIds.contains($0.id) }
        guard !availableWords.isEmpty else { return [] }

        let dueReviewWords = dueReviewWords(in: availableWords, records: records, now: now)
        let dueReviewIDs = Set(dueReviewWords.map(\.id))
        let newWords = stablePreviewOrder(
            availableWords.filter { records[$0.id] == nil },
            salt: "new",
            dayKey: dayKey
        )
        let reinforcementWords = stablePreviewOrder(
            availableWords.filter { records[$0.id] != nil && !dueReviewIDs.contains($0.id) },
            salt: "reinforcement",
            dayKey: dayKey
        )

        var result: [SimpleWord] = []
        result.reserveCapacity(availableWords.count)
        var seenIds: Set<String> = []

        func appendUnique(_ words: [SimpleWord]) {
            for word in words where seenIds.insert(word.id).inserted {
                result.append(word)
            }
        }

        appendUnique(dueReviewWords)
        appendUnique(newWords)
        appendUnique(reinforcementWords)
        return result
    }

    func dueReviewWords(
        in words: [SimpleWord],
        records: [String: LearningRecord],
        now: Date
    ) -> [SimpleWord] {
        words
            .filter { word in
                guard let record = records[word.id] else { return false }
                return record.nextReviewDate <= now
            }
            .sorted { lhs, rhs in
                let lhsDate = records[lhs.id]?.nextReviewDate ?? .distantFuture
                let rhsDate = records[rhs.id]?.nextReviewDate ?? .distantFuture
                if lhsDate == rhsDate { return lhs.id < rhs.id }
                return lhsDate < rhsDate
            }
    }

    private func dailyNewWordQuota(for deckLimit: Int) -> Int {
        guard deckLimit > 0 else { return 0 }
        return max(1, Int(ceil(Double(deckLimit) * newCardQuotaRatio)))
    }

    private func dateByAddingDays(_ days: Int, from date: Date) -> Date {
        let anchor = normalizedReviewDate(date)
        return calendar.date(byAdding: .day, value: days, to: anchor) ?? anchor
    }

    private func stablePreviewOrder(_ words: [SimpleWord], salt: String, dayKey: String) -> [SimpleWord] {
        words.sorted { lhs, rhs in
            let lhsRank = stablePreviewRank(for: lhs.id, salt: salt, dayKey: dayKey)
            let rhsRank = stablePreviewRank(for: rhs.id, salt: salt, dayKey: dayKey)
            if lhsRank == rhsRank {
                return lhs.id < rhs.id
            }
            return lhsRank < rhsRank
        }
    }

    private func stablePreviewRank(for id: String, salt: String, dayKey: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in "\(dayKey)|\(salt)|\(id)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }
}

/// Spaced Repetition System Manager for learning French words
@MainActor
public final class SRSManager: ObservableObject {
    public static let shared = SRSManager()

    enum DailyStudyState: String {
        case noEligibleCards = "no_eligible_cards"
        case inProgress = "in_progress"
        case completed = "completed"
    }

    private enum ReviewOutcome {
        case mastered
        case blurry
        case forgot
    }

    private struct LevelDailyDeckSnapshot: Codable {
        let date: String
        let deckWordIds: [String]
        let swipedDeckWordIds: [String]
        let learningQueueIds: [String]
        let infinitePracticeActive: Bool

        init(
            date: String,
            deckWordIds: [String],
            swipedDeckWordIds: [String],
            learningQueueIds: [String],
            infinitePracticeActive: Bool
        ) {
            self.date = date
            self.deckWordIds = deckWordIds
            self.swipedDeckWordIds = swipedDeckWordIds
            self.learningQueueIds = learningQueueIds
            self.infinitePracticeActive = infinitePracticeActive
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try container.decode(String.self, forKey: .date)
            deckWordIds = try container.decode([String].self, forKey: .deckWordIds)
            swipedDeckWordIds = (try? container.decode([String].self, forKey: .swipedDeckWordIds)) ?? []
            learningQueueIds = try container.decode([String].self, forKey: .learningQueueIds)
            infinitePracticeActive = try container.decodeIfPresent(Bool.self, forKey: .infinitePracticeActive) ?? false
        }
    }

    private struct SyncPayload: Codable {
        let schemaVersion: Int
        let resetVersion: Int?
        let updatedAt: Date
        let sourceDeviceId: String
        let learningRecords: [String: LearningRecord]
        let targetLevel: String
        let dailyDeckLimit: Int
        let dailyDeckWordIds: [String]
        let dailySwipedWordIds: [String]
        let learningQueueIds: [String]
        let levelDailyDeckSnapshots: [String: LevelDailyDeckSnapshot]
        let dailyCompletionRatios: [String: Double]
        let dailyStudyStates: [String: String]
        let isInfinitePracticeActive: Bool
        let dailyDeckDate: String?
    }

    // MARK: - 调度配置
    // 默认每日最多发牌数量。
    private let defaultDailyDeckLimit = 50
    // 用户可选的每日发牌数量。
    private let supportedDailyDeckLimits: Set<Int> = [5, 10, 15, 20, 50]
    private let supportedTargetLevels: Set<String> = ["All", "A1", "A2", "B1", "B2", "C1", "C2"]
    private static let orderedProficiencyLevels: [String] = ["A1", "A2", "B1", "B2", "C1", "C2"]

    private static func nextProficiencyLevel(after level: String) -> String? {
        guard let idx = orderedProficiencyLevels.firstIndex(of: level),
              idx + 1 < orderedProficiencyLevels.count else { return nil }
        return orderedProficiencyLevels[idx + 1]
    }
    // 每日发牌中，新词的最低保障比例（20%）。
    private let newCardQuotaRatio = 0.20
    // 降级（模糊/忘记）后的固定下次复习间隔（天）。
    private let retryIntervalDays = 1

    // MARK: - 外部联动通知
    public static let didMarkForgotWordNotification = Notification.Name("SRSManager.didMarkForgotWord")
    public static let forgotWordIdUserInfoKey = "wordId"
    
    // UserDefaults keys
    private struct Keys {
        static let learningRecords = "learning_records_v1"
        static let targetLevel = "target_level"
        static let dailyDeckLimit = "daily_deck_limit"
        static let dailyDeckDate = "daily_deck_date"
        static let dailyDeckWordIds = "daily_deck_word_ids"
        static let learningQueueIds = "learning_queue_ids"
        static let dailySwipedWordIds = "daily_swiped_word_ids"
        static let levelDailyDeckSnapshots = "level_daily_deck_snapshots_v1"
        static let dailyCompletionRatios = "daily_completion_ratios"
        static let dailyStudyStates = "daily_study_states"
        static let lastLearningStateMutationAt = "learning_state_mutation_at"
        static let learningSyncResetVersion = "learning_sync_reset_version"
        static let iCloudSyncDeviceId = "icloud_sync_device_id"
    }
    
    // Published properties
    @Published private(set) var learningRecords: [String: LearningRecord] = [:]
    @Published private(set) var targetLevel: String = "A1"
    @Published private(set) var dailyDeckLimit: Int = 50
    @Published private(set) var dailyDeckWordIds: [String] = []
    @Published private(set) var dailySwipedWordIds: Set<String> = []
    @Published private(set) var learningQueueIds: [String] = []
    @Published private(set) var dailyCompletionRatios: [String: Double] = [:]
    @Published private(set) var dailyStudyStates: [String: String] = [:]
    @Published private(set) var isInfinitePracticeActive: Bool = false
    private var levelDailyDeckSnapshots: [String: LevelDailyDeckSnapshot] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let iCloudSyncService = ICloudSyncService.shared
    private let calendar = Calendar.current
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private let syncPayloadSchemaVersion = 2
    private var cancellables: Set<AnyCancellable> = []
    private var pendingLearningStateSaveTask: Task<Void, Never>? = nil
    private var lastLearningStateMutationAt: Date = .distantPast
    private var learningSyncResetVersion: Int = 0
    private var isApplyingRemoteSyncPayload = false
    private lazy var iCloudSyncDeviceId: String = loadOrCreateICloudSyncDeviceId()
    private var appState: AppState? = nil

    var forgotWordIds: Set<String> { wordIds(inMemoryState: .forgot) }
    var blurryWordIds: Set<String> { wordIds(inMemoryState: .blurry) }
    var masteredWordIds: Set<String> { wordIds(inMemoryState: .mastered) }

    private var scheduler: SRSScheduler {
        SRSScheduler(
            calendar: calendar,
            newCardQuotaRatio: newCardQuotaRatio,
            retryIntervalDays: retryIntervalDays
        )
    }
    
    private init() {
        loadLearningState()
    }
    
    public func configure(with appState: AppState) {
        self.appState = appState
        let configuredLevel = canonicalTargetLevel(appState.level)
        let today = todayKey()

        if targetLevel != configuredLevel,
           levelDailyDeckSnapshots[configuredLevel]?.date != today {
            dailyDeckWordIds = []
            dailySwipedWordIds = []
            learningQueueIds = []
            isInfinitePracticeActive = false
        }

        targetLevel = configuredLevel
        refreshDailyDeckIfNeeded()
        reconcileDeckWithAvailableWords()
        saveLearningState()
        bindICloudSync(with: appState)
    }

    public func refreshForCurrentDayIfNeeded() {
        refreshDailyDeckIfNeeded()
    }

    public func prepareDiscoverQueueForDisplay() {
        refreshDailyDeckIfNeeded()
        reconcileDeckWithAvailableWords()
        ensureLearningQueueReady()
    }
    
    // MARK: - State Management
    
    private func loadLearningState() {
        // Target Level
        if let savedLevel = userDefaults.string(forKey: Keys.targetLevel) {
            targetLevel = canonicalTargetLevel(savedLevel)
        }

        // Daily Deck Limit
        if let savedLimit = userDefaults.object(forKey: Keys.dailyDeckLimit) as? Int,
           supportedDailyDeckLimits.contains(savedLimit) {
            dailyDeckLimit = savedLimit
        } else {
            dailyDeckLimit = defaultDailyDeckLimit
        }
        
        // Learning Records
        if let recordsData = userDefaults.data(forKey: Keys.learningRecords),
           let records = try? JSONDecoder().decode([String: LearningRecord].self, from: recordsData) {
            learningRecords = records
            normalizeLearningRecordsReviewDates()
        }

        if let mutationAt = userDefaults.object(forKey: Keys.lastLearningStateMutationAt) as? Date {
            lastLearningStateMutationAt = mutationAt
        }
        if let resetVersion = userDefaults.object(forKey: Keys.learningSyncResetVersion) as? Int {
            learningSyncResetVersion = max(0, resetVersion)
        }

        if let savedRatios = userDefaults.dictionary(forKey: Keys.dailyCompletionRatios) {
            dailyCompletionRatios = savedRatios.reduce(into: [:]) { partialResult, pair in
                if let number = pair.value as? NSNumber {
                    partialResult[pair.key] = number.doubleValue
                } else if let value = pair.value as? Double {
                    partialResult[pair.key] = value
                }
            }
        }

        if let savedStates = userDefaults.dictionary(forKey: Keys.dailyStudyStates) {
            dailyStudyStates = savedStates.reduce(into: [:]) { partialResult, pair in
                if let value = pair.value as? String,
                   DailyStudyState(rawValue: value) != nil {
                    partialResult[pair.key] = value
                }
            }
        }
        
        let savedDeckDate = userDefaults.string(forKey: Keys.dailyDeckDate) ?? ""
        let today = todayKey()

        if let snapshotData = userDefaults.data(forKey: Keys.levelDailyDeckSnapshots),
           let snapshots = try? JSONDecoder().decode([String: LevelDailyDeckSnapshot].self, from: snapshotData) {
            levelDailyDeckSnapshots = snapshots
        }
        pruneStaleLevelSnapshots(today: today)

        // Preserve the previous day's snapshot before rotating to a new deck.
        if savedDeckDate != today, !savedDeckDate.isEmpty {
            let savedDeckIds = userDefaults.stringArray(forKey: Keys.dailyDeckWordIds) ?? []
            let savedSwipedIds = Set(userDefaults.stringArray(forKey: Keys.dailySwipedWordIds) ?? [])
            persistHeatmapSnapshotIfNeeded(
                dateKey: savedDeckDate,
                deckWordIds: savedDeckIds,
                swipedDeckWordIds: savedSwipedIds
            )
        }
        pruneHeatmapDataToCurrentYear(today: today)

        if savedDeckDate == today,
           let savedDeckIds = userDefaults.stringArray(forKey: Keys.dailyDeckWordIds) {
            let savedSwipedIds = userDefaults.stringArray(forKey: Keys.dailySwipedWordIds) ?? []
            let savedQueueIds = userDefaults.stringArray(forKey: Keys.learningQueueIds) ?? []
            let existingSnapshot = levelDailyDeckSnapshots[targetLevel]
            levelDailyDeckSnapshots[targetLevel] = LevelDailyDeckSnapshot(
                date: today,
                deckWordIds: savedDeckIds,
                swipedDeckWordIds: savedSwipedIds,
                learningQueueIds: savedQueueIds,
                infinitePracticeActive: existingSnapshot?.infinitePracticeActive ?? false
            )
        }

        if !restoreLevelSnapshotIfAvailable(for: targetLevel, on: today) {
            if savedDeckDate == today {
                if let savedDeckIds = userDefaults.stringArray(forKey: Keys.dailyDeckWordIds) {
                    dailyDeckWordIds = Array(savedDeckIds.prefix(dailyDeckLimit))
                }
                if let savedSwipedIds = userDefaults.stringArray(forKey: Keys.dailySwipedWordIds) {
                    dailySwipedWordIds = Set(savedSwipedIds)
                }
                sanitizeDeckState(preferredQueueIds: userDefaults.stringArray(forKey: Keys.learningQueueIds))
                storeCurrentLevelSnapshot(for: today)
            } else {
                dailyDeckWordIds = []
                dailySwipedWordIds = []
                learningQueueIds = []
                isInfinitePracticeActive = false
            }
        }
    }
    
    private func saveLearningState(touchMutation: Bool = false) {
        pendingLearningStateSaveTask?.cancel()
        pendingLearningStateSaveTask = nil
        let today = todayKey()
        updateTodaySnapshots()
        pruneHeatmapDataToCurrentYear(today: today)
        storeCurrentLevelSnapshot(for: today)

        // Save learning records
        if let recordsData = try? JSONEncoder().encode(learningRecords) {
            userDefaults.set(recordsData, forKey: Keys.learningRecords)
        }
        
        // Save target level
        userDefaults.set(targetLevel, forKey: Keys.targetLevel)
        userDefaults.set(dailyDeckLimit, forKey: Keys.dailyDeckLimit)
        
        // Save daily deck
        userDefaults.set(today, forKey: Keys.dailyDeckDate)
        userDefaults.set(dailyDeckWordIds, forKey: Keys.dailyDeckWordIds)
        userDefaults.set(learningQueueIds, forKey: Keys.learningQueueIds)
        userDefaults.set(Array(dailySwipedWordIds), forKey: Keys.dailySwipedWordIds)
        
        userDefaults.set(dailyCompletionRatios, forKey: Keys.dailyCompletionRatios)
        userDefaults.set(dailyStudyStates, forKey: Keys.dailyStudyStates)
        if let snapshotData = try? JSONEncoder().encode(levelDailyDeckSnapshots) {
            userDefaults.set(snapshotData, forKey: Keys.levelDailyDeckSnapshots)
        }

        if touchMutation && !isApplyingRemoteSyncPayload {
            lastLearningStateMutationAt = Date()
        }
        userDefaults.set(lastLearningStateMutationAt, forKey: Keys.lastLearningStateMutationAt)
        userDefaults.set(learningSyncResetVersion, forKey: Keys.learningSyncResetVersion)

        if touchMutation && !isApplyingRemoteSyncPayload {
            pushLearningStateToICloudIfNeeded()
        }
    }

    public func scheduleLearningStateSave(
        delayNanoseconds: UInt64 = 180_000_000,
        touchMutation: Bool = false
    ) {
        pendingLearningStateSaveTask?.cancel()
        pendingLearningStateSaveTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            saveLearningState(touchMutation: touchMutation)
        }
    }

    private func refreshDailyDeckIfNeeded(knownDeckDate: String? = nil) {
        let today = todayKey()
        let currentDeckDate = knownDeckDate ?? (userDefaults.string(forKey: Keys.dailyDeckDate) ?? "")

        if currentDeckDate != today, !currentDeckDate.isEmpty {
            persistHeatmapSnapshotIfNeeded(
                dateKey: currentDeckDate,
                deckWordIds: dailyDeckWordIds,
                swipedDeckWordIds: dailySwipedWordIds
            )
        }

        pruneHeatmapDataToCurrentYear(today: today)
        pruneStaleLevelSnapshots(today: today)

        if currentDeckDate != today {
            if restoreLevelSnapshotIfAvailable(for: targetLevel, on: today) {
                if dailyDeckWordIds.isEmpty || dailyDeckWordIds.count > dailyDeckLimit {
                    generateDailyDeck()
                } else {
                    sanitizeDeckState()
                }
            } else {
                generateDailyDeck()
            }
            saveLearningState()
            return
        }

        if restoreLevelSnapshotIfAvailable(for: targetLevel, on: today) {
            if dailyDeckWordIds.isEmpty || dailyDeckWordIds.count > dailyDeckLimit {
                generateDailyDeck()
            }
        } else if dailyDeckWordIds.isEmpty || dailyDeckWordIds.count > dailyDeckLimit {
            generateDailyDeck()
        } else {
            sanitizeDeckState()
        }
        saveLearningState()
    }
    
    // MARK: - Learning Actions

    /// 描述一次 swipe 是从哪个 UI 入口来的。
    public enum ReviewSource {
        /// Discover 主牌堆在日课阶段的滑动：计入今日目标。
        case dailyDeck
        /// 日课完成后的 Continue ∞ 加练、银河模式的滑动：不计入今日目标。
        case extraPractice
        /// Search 搜词、Widget 深链等非队列入口：不计入今日目标。
        case lookup
        /// Progress 页展开卡：用户手动整理记忆档案，不计今日目标，不推进当前牌堆。
        case progress

        var countsTowardDailyGoal: Bool {
            self == .dailyDeck
        }

        var advancesQueue: Bool {
            self == .dailyDeck || self == .extraPractice
        }

        var bypassesSameDayMasteryCap: Bool {
            self == .progress
        }

        var usesManualMasteryFloor: Bool {
            self == .progress
        }
    }

    public func markWordMastered(_ wordId: String, source: ReviewSource) {
        recordReview(wordId, outcome: .mastered, source: source)
    }

    public func markWordBlurry(_ wordId: String, source: ReviewSource) {
        recordReview(wordId, outcome: .blurry, source: source)
    }

    public func markWordForgot(_ wordId: String, source: ReviewSource) {
        recordReview(wordId, outcome: .forgot, source: source)
    }

    /// 记录一次复习。
    ///
    /// **统一规则：**
    /// - 日课、Continue ∞、Search/Widget 中，同一张卡若今天已经被滑过一次，任何“升级”方向的滑动（mastered）都会被跳过，档案不变。
    /// - Progress 页右滑是手动整理档案：只把间隔补到掌握下限，不无限加权。
    /// - “降级”方向（blurry/forgot）任何时候都允许写入——错了就该诚实记下。
    /// - 不再有毕业。
    private func recordReview(
        _ wordId: String,
        outcome: ReviewOutcome,
        source: ReviewSource
    ) {
        let now = Date()
        let oldRecord = learningRecords[wordId]

        // 每日升级闸：同一张卡一天内最多升级一次。
        // 降级不受限——用户任何时候都可以说“我其实不会”。
        let reviewedToday = oldRecord?.lastReviewedAt
            .map { calendar.isDate($0, inSameDayAs: now) } ?? false
        let blockedAsDailyUpgrade = reviewedToday && outcome == .mastered && !source.bypassesSameDayMasteryCap
        var didMutateLearningState = false

        if !blockedAsDailyUpgrade {
            learningRecords[wordId] = buildLearningRecord(
                wordId: wordId,
                outcome: outcome,
                source: source,
                oldRecord: oldRecord,
                now: now
            )
            didMutateLearningState = true
        }

        didMutateLearningState = updateQueueAfterReview(
            wordId,
            source: source,
            now: now
        ) || didMutateLearningState

        if outcome == .forgot {
            NotificationCenter.default.post(
                name: Self.didMarkForgotWordNotification,
                object: self,
                userInfo: [Self.forgotWordIdUserInfoKey: wordId]
            )
        }

        if didMutateLearningState {
            // Defer the JSON encode + UserDefaults write off the swipe-completion
            // frame. The heavy save used to land right as the peek card was rising,
            // blocking the main thread and causing a dropped frame in the transition.
            // scheduleLearningStateSave coalesces rapid swipes into a single save.
            scheduleLearningStateSave(touchMutation: true)
        }
    }

    private func buildLearningRecord(
        wordId: String,
        outcome: ReviewOutcome,
        source: ReviewSource,
        oldRecord: LearningRecord?,
        now: Date
    ) -> LearningRecord {
        let currentInterval = oldRecord?.intervalDays ?? 0
        switch outcome {
        case .mastered:
            if source.usesManualMasteryFloor {
                // Progress 页是用户手动整理档案：补到掌握下限，但不借机无限升级。
                let nextInterval = max(currentInterval, SRSRules.masteredIntervalThreshold)
                return LearningRecord(
                    wordId: wordId,
                    intervalDays: nextInterval,
                    nextReviewDate: scheduler.scheduledReviewDate(forInterval: nextInterval, from: now),
                    lastReviewedAt: now
                )
            }
            // 右滑：间隔沿梯度上升。
            let nextInterval = scheduler.nextMasteryInterval(from: currentInterval)
            return LearningRecord(
                wordId: wordId,
                intervalDays: nextInterval,
                nextReviewDate: scheduler.scheduledReviewDate(forInterval: nextInterval, from: now),
                lastReviewedAt: now
            )
        case .blurry:
            // 下滑：间隔保持不变，但明天再看一次（临时降级）。
            return LearningRecord(
                wordId: wordId,
                intervalDays: currentInterval,
                nextReviewDate: scheduler.retryReviewDate(from: now),
                lastReviewedAt: now
            )
        case .forgot:
            // 左滑：间隔归零，明天重头再来。
            return LearningRecord(
                wordId: wordId,
                intervalDays: 0,
                nextReviewDate: scheduler.retryReviewDate(from: now),
                lastReviewedAt: now
            )
        }
    }

    @discardableResult
    private func updateQueueAfterReview(
        _ wordId: String,
        source: ReviewSource,
        now: Date
    ) -> Bool {
        var didMutateQueueState = false

        // 仅 dailyDeck 来源 & 该词确实在今天这副牌里时，才计入今日目标进度。
        if source.countsTowardDailyGoal, dailyDeckWordIds.contains(wordId) {
            didMutateQueueState = dailySwipedWordIds.insert(wordId).inserted || didMutateQueueState
        }

        // 只有队列入口推进队列；lookup/progress 只写记忆档案，不影响当前牌堆。
        guard source.advancesQueue else { return didMutateQueueState }
        let previousQueueIds = learningQueueIds
        removeWordFromLearningQueue(wordId)
        refillInfiniteQueueIfNeeded(now: now)
        return didMutateQueueState || previousQueueIds != learningQueueIds
    }

    public func resetWordToNew(_ wordId: String) {
        learningRecords.removeValue(forKey: wordId)
        dailySwipedWordIds.remove(wordId)
        refreshCurrentDeckState(afterMutating: wordId)
        saveLearningState(touchMutation: true)
    }

    public func resetLearningData() {
        bumpLearningSyncResetVersion()
        learningRecords = [:]
        dailyDeckWordIds = []
        dailySwipedWordIds = []
        learningQueueIds = []
        dailyCompletionRatios = [:]
        dailyStudyStates = [:]
        isInfinitePracticeActive = false
        levelDailyDeckSnapshots = [:]
        if let appState {
            targetLevel = appState.level
        }
        rebuildDeck(now: Date())
        saveLearningState(touchMutation: true)
    }
    
    // MARK: - Daily Deck
    
    private func generateDailyDeck() {
        rebuildDeck(now: Date())
    }

    private func pruneStaleLevelSnapshots(today: String) {
        levelDailyDeckSnapshots = levelDailyDeckSnapshots.filter { _, snapshot in
            snapshot.date == today
        }
    }

    private func storeCurrentLevelSnapshot(for date: String) {
        pruneStaleLevelSnapshots(today: date)
        levelDailyDeckSnapshots[targetLevel] = LevelDailyDeckSnapshot(
            date: date,
            deckWordIds: dailyDeckWordIds,
            swipedDeckWordIds: Array(dailySwipedWordIds),
            learningQueueIds: learningQueueIds,
            infinitePracticeActive: isInfinitePracticeActive
        )
    }

    @discardableResult
    private func restoreLevelSnapshotIfAvailable(for level: String, on date: String) -> Bool {
        guard let snapshot = levelDailyDeckSnapshots[level], snapshot.date == date else {
            return false
        }
        apply(snapshot: snapshot)
        return true
    }

    private func apply(snapshot: LevelDailyDeckSnapshot) {
        dailyDeckWordIds = Array(snapshot.deckWordIds.prefix(dailyDeckLimit))
        isInfinitePracticeActive = snapshot.infinitePracticeActive
        dailySwipedWordIds = Set(snapshot.swipedDeckWordIds)
        sanitizeDeckState(preferredQueueIds: snapshot.learningQueueIds)
    }

    private func buildDailyDeck(from allWords: [SimpleWord], now: Date, deckLimit: Int) -> [SimpleWord] {
        let levelFilteredWords = wordsForTargetLevel(from: allWords)
        return scheduler.buildDailyDeck(
            from: levelFilteredWords,
            records: learningRecords,
            now: now,
            deckLimit: deckLimit
        )
    }
    
    // MARK: - Helper Functions

    private func rebuildDeck(now: Date) {
        guard let appState = appState else { return }
        isInfinitePracticeActive = false
        let deck = buildDailyDeck(from: appState.words, now: now, deckLimit: dailyDeckLimit)
        dailyDeckWordIds = deck.map(\.id)
        dailySwipedWordIds.removeAll()
        rebuildLearningQueueFromDeck()
    }
    
    private func todayKey() -> String {
        dayKey(for: Date())
    }

    private func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func persistHeatmapSnapshotIfNeeded(
        dateKey: String,
        deckWordIds: [String],
        swipedDeckWordIds: Set<String>
    ) {
        guard !dateKey.isEmpty else { return }
        guard !deckWordIds.isEmpty else {
            if dailyCompletionRatios[dateKey] == nil,
               dailyStudyStates[dateKey] == nil {
                dailyStudyStates[dateKey] = DailyStudyState.noEligibleCards.rawValue
            }
            return
        }
        let swipedCount = deckWordIds.filter { swipedDeckWordIds.contains($0) }.count
        let ratio = deckWordIds.isEmpty ? 0 : Double(swipedCount) / Double(deckWordIds.count)
        dailyCompletionRatios[dateKey] = max(dailyCompletionRatios[dateKey] ?? 0, ratio)
        dailyStudyStates[dateKey] = stateFrom(
            deckCount: deckWordIds.count,
            completedCount: swipedCount
        ).rawValue
    }

    private func normalizedReviewDate(_ date: Date) -> Date {
        scheduler.normalizedReviewDate(date)
    }

    private func normalizeLearningRecordsReviewDates() {
        learningRecords = learningRecords.reduce(into: [:]) { partialResult, pair in
            let record = pair.value
            let normalizedDate = normalizedReviewDate(record.nextReviewDate)
            partialResult[pair.key] = LearningRecord(
                wordId: record.wordId,
                intervalDays: record.intervalDays,
                nextReviewDate: normalizedDate,
                lastReviewedAt: record.lastReviewedAt
            )
        }
    }


    func setTargetLevel(_ level: String) {
        let normalizedLevel = canonicalTargetLevel(level)
        guard targetLevel != normalizedLevel else { return }
        targetLevel = normalizedLevel
        resetTodayProgressForPlanChange(now: Date())
        saveLearningState(touchMutation: true)
    }

    func setDailyDeckLimit(_ limit: Int) {
        let normalizedLimit = supportedDailyDeckLimits.contains(limit) ? limit : defaultDailyDeckLimit
        guard dailyDeckLimit != normalizedLimit else { return }
        dailyDeckLimit = normalizedLimit
        resetTodayProgressForPlanChange(now: Date())
        saveLearningState(touchMutation: true)
    }

    private func resetTodayProgressForPlanChange(now: Date) {
        let today = todayKey()
        levelDailyDeckSnapshots.removeAll()
        dailyCompletionRatios.removeValue(forKey: today)
        dailyStudyStates.removeValue(forKey: today)
        rebuildDeck(now: now)
    }

    private func pruneHeatmapDataToCurrentYear(today: String) {
        guard today.count >= 4 else { return }
        let yearPrefix = String(today.prefix(4)) + "-"
        dailyCompletionRatios = dailyCompletionRatios.filter { $0.key.hasPrefix(yearPrefix) }
        dailyStudyStates = dailyStudyStates.filter { $0.key.hasPrefix(yearPrefix) }
    }

    private func extendTodayDeckIfNeeded(now: Date) {
        guard let appState = appState else { return }
        guard dailyDeckWordIds.count < dailyDeckLimit else { return }

        let existingDeckSet = Set(dailyDeckWordIds)
        let requiredAdditionalCount = dailyDeckLimit - dailyDeckWordIds.count
        guard requiredAdditionalCount > 0 else { return }

        let candidateDeck = buildDailyDeck(
            from: appState.words,
            now: now,
            deckLimit: dailyDeckLimit
        )

        var additionalWordIds: [String] = []
        var additionalWordIdSet: Set<String> = []
        for word in candidateDeck {
            guard !existingDeckSet.contains(word.id) else { continue }
            guard additionalWordIdSet.insert(word.id).inserted else { continue }
            additionalWordIds.append(word.id)
            if additionalWordIds.count >= requiredAdditionalCount {
                break
            }
        }

        guard !additionalWordIds.isEmpty else { return }

        dailyDeckWordIds.append(contentsOf: additionalWordIds)

        let swipedSet = dailySwipedWordIds
        for id in additionalWordIds where !swipedSet.contains(id) {
            learningQueueIds.append(id)
        }
    }

    private func removeWordFromLearningQueue(_ wordId: String) {
        learningQueueIds.removeAll { $0 == wordId }
    }

    private func rebuildLearningQueueFromDeck() {
        sanitizeDeckState(preferredQueueIds: dailyDeckWordIds)
    }

    private func refreshCurrentDeckState(afterMutating wordId: String? = nil) {
        guard let wordId, dailyDeckWordIds.contains(wordId), !dailySwipedWordIds.contains(wordId) else {
            sanitizeDeckState()
            return
        }
        sanitizeDeckState(preferredQueueIds: [wordId] + learningQueueIds)
    }
    
    public func ensureLearningQueueReady() {
        refillInfiniteQueueIfNeeded(now: Date())
        guard let appState = appState else { return }
        var resolved = learningQueueIds.compactMap { appState.getWordById($0) }
        if resolved.isEmpty,
           isInfinitePracticeActive,
           !learningQueueIds.isEmpty {
            learningQueueIds = []
            refillInfiniteQueueIfNeeded(now: Date())
            resolved = learningQueueIds.compactMap { appState.getWordById($0) }
        }
        if resolved.isEmpty,
           !isInfinitePracticeActive,
           todayStudyState == .completed,
           hasCompletedDailyGoal {
            completeDailyGoalAndEnterInfinitePractice()
            resolved = learningQueueIds.compactMap { appState.getWordById($0) }
        }
        if resolved.isEmpty,
           !isInfinitePracticeActive,
           todayStudyState == .inProgress {
            rebuildLearningQueueFromDeck()
            var repaired = learningQueueIds.compactMap { appState.getWordById($0) }
            if repaired.isEmpty {
                generateDailyDeck()
                repaired = learningQueueIds.compactMap { appState.getWordById($0) }
            }
            saveLearningState()
        }
    }

    public func getLearningQueueWordsSnapshot() -> [SimpleWord] {
        guard let appState = appState else { return [] }
        return learningQueueIds.compactMap { appState.getWordById($0) }
    }

    public func getLearningQueueWords() -> [SimpleWord] {
        ensureLearningQueueReady()
        return getLearningQueueWordsSnapshot()
    }

    public func promoteWordToLearningQueueFront(_ wordId: String, persist: Bool = true) {
        guard !wordId.isEmpty else { return }
        guard let appState, appState.getWordById(wordId) != nil else { return }
        ensureLearningQueueReady()

        if !isInfinitePracticeActive {
            ensureWordInDailyDeckFront(wordId)
        }

        sanitizeDeckState(preferredQueueIds: [wordId] + learningQueueIds)
        if persist {
            saveLearningState()
        }
    }

    private func ensureWordInDailyDeckFront(_ wordId: String) {
        dailySwipedWordIds.remove(wordId)
        guard !dailyDeckWordIds.contains(wordId) else { return }
        dailyDeckWordIds.insert(wordId, at: 0)
        trimDailyDeckOverflowIfNeeded()
    }

    private func trimDailyDeckOverflowIfNeeded() {
        while dailyDeckWordIds.count > dailyDeckLimit, let removedId = dailyDeckWordIds.popLast() {
            dailySwipedWordIds.remove(removedId)
            learningQueueIds.removeAll { $0 == removedId }
        }
    }

    public func getUpcomingPreviewWords(limit: Int = 25, excludingCurrentWordId currentWordId: String? = nil) -> [SimpleWord] {
        guard limit > 0 else { return [] }

        let now = Date()
        refillInfiniteQueueIfNeeded(now: now)
        guard let appState else { return [] }

        var orderedIds: [String] = []
        orderedIds.reserveCapacity(limit)
        var seenIds: Set<String> = []
        var blockedIds = Set(dailySwipedWordIds)
        if let currentWordId, !currentWordId.isEmpty {
            blockedIds.insert(currentWordId)
        }

        func appendIds<S: Sequence>(_ ids: S) where S.Element == String {
            for id in ids {
                guard !blockedIds.contains(id) else { continue }
                guard seenIds.insert(id).inserted else { continue }
                guard appState.getWordById(id) != nil else { continue }
                orderedIds.append(id)
                if orderedIds.count >= limit { return }
            }
        }

        appendIds(learningQueueIds)

        if orderedIds.count < limit {
            let unresolvedDeckIds = dailyDeckWordIds.filter { !dailySwipedWordIds.contains($0) }
            appendIds(unresolvedDeckIds)
        }

        if orderedIds.count < limit {
            let excludedIds = blockedIds.union(seenIds).union(Set(dailyDeckWordIds))
            let continuationWords = buildPreviewContinuation(from: appState.words, now: now, excluding: excludedIds)
            appendIds(continuationWords.map(\.id))
        }

        return orderedIds.prefix(limit).compactMap { appState.getWordById($0) }
    }
    
    func getDailyDeckWords() -> [SimpleWord] {
        guard let appState = appState else { return [] }
        return dailyDeckWordIds.compactMap { appState.getWordById($0) }
    }

    private func words(inMemoryState state: LearningMemoryState) -> [SimpleWord] {
        guard let appState = appState else { return [] }
        return learningRecords.values
            .filter { $0.memoryState == state }
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastReviewedAt ?? lhs.nextReviewDate
                let rhsDate = rhs.lastReviewedAt ?? rhs.nextReviewDate
                if lhsDate == rhsDate { return lhs.wordId < rhs.wordId }
                return lhsDate > rhsDate
            }
            .compactMap { appState.getWordById($0.wordId) }
    }
    
    public func getMasteredWords() -> [SimpleWord] {
        words(inMemoryState: .mastered)
    }
    
    public func getBlurryWords() -> [SimpleWord] {
        words(inMemoryState: .blurry)
    }
    
    public func getForgotWords() -> [SimpleWord] {
        words(inMemoryState: .forgot)
    }

    private func wordIds(inMemoryState state: LearningMemoryState) -> Set<String> {
        Set(learningRecords.values.lazy
            .filter { $0.memoryState == state }
            .map(\.wordId))
    }

    private var todayDeckSwipedCount: Int {
        dailySwipedWordIds.count
    }

    var hasCompletedDailyGoal: Bool {
        let goalCount = dailyDeckWordIds.count
        guard goalCount > 0 else { return false }
        return todayDeckSwipedCount >= goalCount
    }

    public func isCurrentLevelLexiconFullyMastered(allWords: [SimpleWord]) -> Bool {
        let level = targetLevel
        guard level != "All" else { return false }
        let levelWords = allWords.filter { $0.level == level }
        guard !levelWords.isEmpty else { return false }
        for word in levelWords {
            guard let record = learningRecords[word.id],
                  record.memoryState == .mastered else {
                return false
            }
        }
        return true
    }

    public func completeDailyGoalAndEnterInfinitePractice() {
        guard hasCompletedDailyGoal else { return }
        guard let appState else { return }

        let sourceLevel = infinitePracticeSourceLevel(afterCompleting: targetLevel, allWords: appState.words)
        if sourceLevel != targetLevel {
            targetLevel = sourceLevel
        }
        if appState.level != sourceLevel {
            appState.level = sourceLevel
        }

        activateInfinitePracticeAndRefill()
    }

    private func infinitePracticeSourceLevel(afterCompleting level: String, allWords: [SimpleWord]) -> String {
        let normalizedLevel = canonicalTargetLevel(level)
        guard normalizedLevel != "All",
              isCurrentLevelLexiconFullyMastered(allWords: allWords),
              let next = Self.nextProficiencyLevel(after: normalizedLevel) else {
            return normalizedLevel
        }
        return next
    }

    private func activateInfinitePracticeAndRefill() {
        learningQueueIds = []
        isInfinitePracticeActive = true
        refillInfiniteQueueIfNeeded(now: Date())
        saveLearningState(touchMutation: true)
    }

    var todayDeckCompletionRatio: Double {
        guard !dailyDeckWordIds.isEmpty else { return 0 }
        let ratio = Double(todayDeckSwipedCount) / Double(dailyDeckWordIds.count)
        return min(max(ratio, 0), 1)
    }

    var todayStudyState: DailyStudyState {
        stateFrom(deckCount: dailyDeckWordIds.count, completedCount: todayDeckSwipedCount)
    }

    var hasNoEligibleCardsToday: Bool {
        todayStudyState == .noEligibleCards
    }

    func deckCompletionRatio(for date: Date) -> Double {
        let key = dayFormatter.string(from: calendar.startOfDay(for: date))
        if key == todayKey() {
            return todayDeckCompletionRatio
        }
        return min(max(dailyCompletionRatios[key] ?? 0, 0), 1)
    }

    func studyState(for date: Date) -> DailyStudyState {
        let key = dayFormatter.string(from: calendar.startOfDay(for: date))
        if key == todayKey() {
            return todayStudyState
        }
        if let rawValue = dailyStudyStates[key],
           let state = DailyStudyState(rawValue: rawValue) {
            return state
        }

        if let storedRatio = dailyCompletionRatios[key] {
            let ratio = min(max(storedRatio, 0), 1)
            if ratio >= 1 { return .completed }
            return .inProgress
        }
        return .noEligibleCards
    }

    private func stateFrom(deckCount: Int, completedCount: Int) -> DailyStudyState {
        guard deckCount > 0 else { return .noEligibleCards }
        return completedCount >= deckCount ? .completed : .inProgress
    }

    private func updateTodaySnapshots() {
        let key = todayKey()
        dailyCompletionRatios[key] = todayDeckCompletionRatio
        dailyStudyStates[key] = todayStudyState.rawValue
    }

    private func refillInfiniteQueueIfNeeded(now: Date) {
        guard isInfinitePracticeActive else { return }
        guard learningQueueIds.count <= 1 else { return }
        guard let appState = appState else { return }

        let batchSize = max(12, dailyDeckLimit)
        let levelWords = wordsForTargetLevel(from: appState.words)
        guard !levelWords.isEmpty else { return }

        // Exclude whatever is still in the queue to avoid duplicates
        let currentIds = Set(learningQueueIds)
        let candidateWords = levelWords.filter { !currentIds.contains($0.id) }
        guard !candidateWords.isEmpty else { return }

        var batch = scheduler.buildInfinitePracticeBatch(
            from: candidateWords,
            records: learningRecords,
            now: now,
            batchSize: batchSize
        )
        if batch.isEmpty {
            batch = Array(candidateWords.shuffled().prefix(batchSize))
        }
        // Append behind any remaining card rather than replacing it
        learningQueueIds = learningQueueIds + batch.map(\.id)
    }

    private func buildPreviewContinuation(from allWords: [SimpleWord], now: Date, excluding excludedIds: Set<String>) -> [SimpleWord] {
        scheduler.buildPreviewContinuation(
            from: wordsForTargetLevel(from: allWords),
            records: learningRecords,
            now: now,
            excluding: excludedIds,
            dayKey: todayKey()
        )
    }

    private func wordsForTargetLevel(from allWords: [SimpleWord]) -> [SimpleWord] {
        if targetLevel == "All" {
            return allWords
        }
        return allWords.filter { $0.level == targetLevel }
    }

    private func canonicalTargetLevel(_ rawLevel: String) -> String {
        let trimmed = rawLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "All" }

        if trimmed == "全部" || trimmed == "सभी" {
            return "All"
        }

        let upper = trimmed.uppercased()
        if upper == "ALL" {
            return "All"
        }
        if supportedTargetLevels.contains(upper) {
            return upper
        }
        if supportedTargetLevels.contains(trimmed) {
            return trimmed
        }
        return "All"
    }

    private func sanitizeDeckState(preferredQueueIds: [String]? = nil) {
        if let appState, appState.hasCompletedInitialResourceLoad {
            let validWordIds = Set(appState.words.map(\.id))
            if !validWordIds.isEmpty {
                dailyDeckWordIds = dailyDeckWordIds.filter { validWordIds.contains($0) }
                dailySwipedWordIds = dailySwipedWordIds.intersection(Set(dailyDeckWordIds))
                learningQueueIds = learningQueueIds.filter { validWordIds.contains($0) }
            }
        }

        let queueSource = preferredQueueIds ?? learningQueueIds

        if isInfinitePracticeActive {
            learningQueueIds = deduplicatedQueue(from: queueSource)
            return
        }

        let deckSet = Set(dailyDeckWordIds)
        dailySwipedWordIds = dailySwipedWordIds.intersection(deckSet)
        let unresolvedSet = deckSet.subtracting(dailySwipedWordIds)
        learningQueueIds = normalizedQueue(
            from: queueSource,
            unresolvedSet: unresolvedSet,
            deckOrder: dailyDeckWordIds
        )
    }

    private func normalizedQueue(from source: [String], unresolvedSet: Set<String>, deckOrder: [String]) -> [String] {
        guard !unresolvedSet.isEmpty else { return [] }

        var queue: [String] = []
        queue.reserveCapacity(deckOrder.count)
        var seen: Set<String> = []

        for id in source where unresolvedSet.contains(id) {
            if seen.insert(id).inserted {
                queue.append(id)
            }
        }

        for id in deckOrder where unresolvedSet.contains(id) {
            if seen.insert(id).inserted {
                queue.append(id)
            }
        }

        return queue
    }

    private func deduplicatedQueue(from source: [String]) -> [String] {
        var queue: [String] = []
        queue.reserveCapacity(source.count)
        var seen: Set<String> = []

        for id in source {
            if seen.insert(id).inserted {
                queue.append(id)
            }
        }

        return queue
    }

    // MARK: - iCloud Sync

    private func bindICloudSync(with appState: AppState) {
        cancellables.removeAll()

        appState.$iCloudSyncEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.handleICloudSyncToggleChanged(isEnabled)
            }
            .store(in: &cancellables)

        appState.$words
            .dropFirst()
            .sink { [weak self] _ in
                self?.reconcileDeckWithAvailableWords()
            }
            .store(in: &cancellables)

        appState.$hasCompletedInitialResourceLoad
            .removeDuplicates()
            .sink { [weak self] loaded in
                guard loaded else { return }
                self?.reconcileDeckWithAvailableWords()
            }
            .store(in: &cancellables)
    }

    private func reconcileDeckWithAvailableWords() {
        guard let appState else { return }
        guard appState.hasCompletedInitialResourceLoad else { return }
        let validWordIds = Set(appState.words.map(\.id))
        guard !validWordIds.isEmpty else { return }

        let prunedLearningState = pruneLearningState(using: validWordIds)
        let previousDeckIds = dailyDeckWordIds
        let previousQueueIds = learningQueueIds
        let previousSwipedDeckIds = dailySwipedWordIds

        dailyDeckWordIds = dailyDeckWordIds.filter { validWordIds.contains($0) }
        dailySwipedWordIds = dailySwipedWordIds.intersection(Set(dailyDeckWordIds))
        learningQueueIds = learningQueueIds.filter { validWordIds.contains($0) }

        if dailyDeckWordIds.isEmpty {
            generateDailyDeck()
        } else {
            if dailyDeckWordIds.count < dailyDeckLimit {
                extendTodayDeckIfNeeded(now: Date())
            }
            sanitizeDeckState()
        }

        if previousDeckIds != dailyDeckWordIds ||
            previousQueueIds != learningQueueIds ||
            previousSwipedDeckIds != dailySwipedWordIds ||
            prunedLearningState {
            saveLearningState()
        }
    }

    private func pruneLearningState(using validWordIds: Set<String>) -> Bool {
        var didPrune = false

        let filteredRecords = learningRecords.filter { validWordIds.contains($0.key) }
        if filteredRecords.count != learningRecords.count {
            learningRecords = filteredRecords
            didPrune = true
        }

        return didPrune
    }

    private func handleICloudSyncToggleChanged(_ isEnabled: Bool) {
        iCloudSyncService.configure(isEnabled: isEnabled) { [weak self] payloadData in
            self?.applyRemoteSyncPayloadIfNewer(payloadData)
        }

        guard isEnabled else { return }
        if iCloudSyncService.payloadData() == nil {
            pushLearningStateToICloudIfNeeded(force: true)
        }
    }

    private func pushLearningStateToICloudIfNeeded(force: Bool = false) {
        guard appState?.iCloudSyncEnabled == true else { return }
        guard !isApplyingRemoteSyncPayload else { return }
        if adoptRemotePayloadIfResetVersionIsHigher() { return }

        if force {
            lastLearningStateMutationAt = Date()
            userDefaults.set(lastLearningStateMutationAt, forKey: Keys.lastLearningStateMutationAt)
        }

        let updatedAt = lastLearningStateMutationAt == .distantPast ? Date() : lastLearningStateMutationAt
        let payload = SyncPayload(
            schemaVersion: syncPayloadSchemaVersion,
            resetVersion: learningSyncResetVersion,
            updatedAt: updatedAt,
            sourceDeviceId: iCloudSyncDeviceId,
            learningRecords: learningRecords,
            targetLevel: targetLevel,
            dailyDeckLimit: dailyDeckLimit,
            dailyDeckWordIds: dailyDeckWordIds,
            dailySwipedWordIds: Array(dailySwipedWordIds).sorted(),
            learningQueueIds: learningQueueIds,
            levelDailyDeckSnapshots: levelDailyDeckSnapshots,
            dailyCompletionRatios: dailyCompletionRatios,
            dailyStudyStates: dailyStudyStates,
            isInfinitePracticeActive: isInfinitePracticeActive,
            dailyDeckDate: userDefaults.string(forKey: Keys.dailyDeckDate) ?? todayKey()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let payloadData = try? encoder.encode(payload) else { return }
        iCloudSyncService.push(payload: payloadData)
    }

    private func applyRemoteSyncPayloadIfNewer(_ payloadData: Data) {
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(SyncPayload.self, from: payloadData) else { return }
        guard payload.schemaVersion == syncPayloadSchemaVersion else { return }
        guard payload.sourceDeviceId != iCloudSyncDeviceId else { return }
        let remoteResetVersion = normalizedResetVersion(payload.resetVersion)
        guard remoteResetVersion >= learningSyncResetVersion else { return }
        if remoteResetVersion == learningSyncResetVersion {
            guard payload.updatedAt > lastLearningStateMutationAt else { return }
        }

        isApplyingRemoteSyncPayload = true
        defer { isApplyingRemoteSyncPayload = false }

        learningRecords = payload.learningRecords
        normalizeLearningRecordsReviewDates()
        targetLevel = canonicalTargetLevel(payload.targetLevel)
        dailyDeckLimit = supportedDailyDeckLimits.contains(payload.dailyDeckLimit)
            ? payload.dailyDeckLimit
            : defaultDailyDeckLimit
        dailyDeckWordIds = payload.dailyDeckWordIds
        dailySwipedWordIds = Set(payload.dailySwipedWordIds)
        learningQueueIds = payload.learningQueueIds
        levelDailyDeckSnapshots = payload.levelDailyDeckSnapshots
        dailyCompletionRatios = payload.dailyCompletionRatios
        dailyStudyStates = payload.dailyStudyStates.filter { DailyStudyState(rawValue: $0.value) != nil }
        isInfinitePracticeActive = payload.isInfinitePracticeActive

        if let appState {
            let validWordIds = Set(appState.words.map(\.id))
            if !validWordIds.isEmpty {
                _ = pruneLearningState(using: validWordIds)
            }
        }
        sanitizeDeckState(preferredQueueIds: payload.learningQueueIds)

        lastLearningStateMutationAt = payload.updatedAt
        learningSyncResetVersion = remoteResetVersion
        userDefaults.set(lastLearningStateMutationAt, forKey: Keys.lastLearningStateMutationAt)
        userDefaults.set(learningSyncResetVersion, forKey: Keys.learningSyncResetVersion)

        if appState?.level != targetLevel {
            appState?.level = targetLevel
        }

        let remoteDeckDate = payload.dailyDeckDate
            ?? payload.levelDailyDeckSnapshots[payload.targetLevel]?.date
            ?? payload.levelDailyDeckSnapshots.values.first?.date
            ?? todayKey()

        refreshDailyDeckIfNeeded(knownDeckDate: remoteDeckDate)
    }

    private func normalizedResetVersion(_ value: Int?) -> Int {
        max(0, value ?? 0)
    }

    private func bumpLearningSyncResetVersion() {
        if learningSyncResetVersion < Int.max {
            learningSyncResetVersion += 1
        }
    }

    private func adoptRemotePayloadIfResetVersionIsHigher() -> Bool {
        guard let payloadData = iCloudSyncService.payloadData() else { return false }
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(SyncPayload.self, from: payloadData) else { return false }
        guard payload.sourceDeviceId != iCloudSyncDeviceId else { return false }
        guard normalizedResetVersion(payload.resetVersion) > learningSyncResetVersion else { return false }
        applyRemoteSyncPayloadIfNewer(payloadData)
        return true
    }

    private func loadOrCreateICloudSyncDeviceId() -> String {
        if let saved = userDefaults.string(forKey: Keys.iCloudSyncDeviceId), !saved.isEmpty {
            return saved
        }
        let created = UUID().uuidString
        userDefaults.set(created, forKey: Keys.iCloudSyncDeviceId)
        return created
    }
}
