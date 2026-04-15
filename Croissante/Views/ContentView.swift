import SwiftUI
import AVFoundation
import StoreKit
import WidgetKit
import UserNotifications
#if os(iOS)
import UIKit
import CoreMotion
#endif

private enum MainTab: CaseIterable, Hashable {
    case explore
    case progress
    case settings
    case search
}

private struct SettingsAvatarBottomPreferenceKey: PreferenceKey {
    nonisolated static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct AppIconPickerLayout {
    let tileSize: CGFloat
    let contentInset: CGFloat
    let bottomInset: CGFloat
    let initialDropTopInset: CGFloat
    let initialDropSpacing: CGFloat

    var sheetInsets: EdgeInsets {
        EdgeInsets(
            top: contentInset,
            leading: contentInset,
            bottom: bottomInset,
            trailing: contentInset
        )
    }
}

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var srsManager: SRSManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var discoverQueueIndex = 0
    @State private var searchSheetShowing = false
    @State private var selectedTab: MainTab = .explore
    @State private var lastContentTab: MainTab = .explore
    @State private var settingsGearSpinToken = 0
    @State private var spotlightWord: SimpleWord?
    @State private var widgetOpenedWordId: String?
    @State private var pendingSettingsMemberPaywall = false
    @State private var isGalaxyVisibleInExplore = false
    @State private var pendingGalaxyTabBarRevealTask: Task<Void, Never>? = nil
    private let galaxyTabBarRevealDelay: UInt64 = 180_000_000

    public init() {}

    private var discoverWords: [SimpleWord] {
        srsManager.getLearningQueueWordsSnapshot()
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var appBackgroundGradient: LinearGradient {
        AppColors.appBackgroundGradient(themeMode: appState.themeMode, isDarkMode: isDarkMode)
    }

    @ViewBuilder
    private var wallpaperBackground: some View {
        ThemedBackgroundView(
            themeMode: appState.themeMode,
            isDarkMode: isDarkMode,
            showWallpaper: shouldShowHomeWallpaper
        )
    }

    private var shouldShowHomeWallpaper: Bool {
        appState.themeMode == .steppe
    }

    private var exploreView: some View {
        DiscoverScreen(
            words: discoverWords,
            queueIndex: $discoverQueueIndex,
            isActiveTab: selectedTab == .explore,
            onGalaxyVisibilityChanged: { [self] visible in
                setExploreGalaxyVisibility(visible)
            },
            onSwipeForgot: { [self] id in
                markDiscoverWordForgot(id)
            },
            onSwipeMastered: { [self] id in
                markDiscoverWordMastered(id)
            },
            onSwipeBlurry: { [self] id in
                markDiscoverWordBlurry(id)
            }
        )
    }

    private var progressView: some View {
        ProgressScreen()
            .environmentObject(appState)
            .environmentObject(srsManager)
            .background {
                wallpaperBackground
            }
    }

    private var settingsView: some View {
        SettingsScreen(pendingMemberPaywall: $pendingSettingsMemberPaywall)
            .environmentObject(appState)
            .background {
                wallpaperBackground
            }
    }

    public var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab(appState.localized("Explore", "探索", "एक्सप्लोर"), systemImage: "siri", value: .explore) {
                    exploreView
                }
                Tab(appState.localized("Progress", "进度", "प्रगति"), systemImage: "figure.run.square.stack.fill", value: .progress) {
                    progressView
                }
                Tab(appState.localized("Settings", "设置", "सेटिंग्स"), systemImage: "gear", value: .settings) {
                    settingsView
                }
                Tab(appState.localized("Search", "搜索", "खोज"), systemImage: "magnifyingglass", value: .search, role: .search) {
                    Color.clear
                        .ignoresSafeArea()
                }
            }
        }
        #if os(iOS)
        .background(
            SettingsTabGearAnimationBridge(
                settingsIndex: 2,
                spinToken: settingsGearSpinToken,
                isTabBarHidden: isGalaxyVisibleInExplore
            )
                .frame(width: 0, height: 0)
        )
        #endif
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .tint(Color(red: 0.02, green: 0.48, blue: 1.00))
        .onChange(of: selectedTab) { _, newTab in
            guard newTab == .search else {
                lastContentTab = newTab
                if newTab != .explore {
                    setExploreGalaxyVisibility(false, delayReveal: false)
                }
                if newTab == .settings {
                    settingsGearSpinToken += 1
                }
                return
            }

            selectedTab = lastContentTab
            searchSheetShowing = true
        }
        .modifier(
            SearchPresentationModifier(
                isPresented: $searchSheetShowing,
                allWords: appState.words,
                searchIndex: appState.wordSearchIndex
            )
        )
        .onAppear {
            guard appState.hasCompletedInitialResourceLoad else { return }
            presentSpotlightWordIfAvailable(appState.spotlightSelectedWordId)
            presentWidgetWordIfAvailable(appState.widgetSelectedWordId)
        }
        .onChange(of: appState.level) { _, newLevel in
            srsManager.setTargetLevel(newLevel)
            advanceDiscover()
        }
        .onChange(of: appState.spotlightSelectedWordId) { _, wordId in
            presentSpotlightWordIfAvailable(wordId)
        }
        .onChange(of: appState.widgetSelectedWordId) { _, wordId in
            presentWidgetWordIfAvailable(wordId)
        }
        .onChange(of: appState.hasCompletedInitialResourceLoad) { _, loaded in
            guard loaded else { return }
            presentSpotlightWordIfAvailable(appState.spotlightSelectedWordId)
            presentWidgetWordIfAvailable(appState.widgetSelectedWordId)
        }
        .onChange(of: appState.openMemberPaywallFromDeepLink) { _, open in
            guard open else { return }
            appState.openMemberPaywallFromDeepLink = false
            selectedTab = .settings
            pendingSettingsMemberPaywall = true
        }
        #if os(iOS)
        .fullScreenCover(item: $spotlightWord) { word in
            let openedFromWidget = widgetOpenedWordId == word.id
            SearchSelectedWordCardView(
                word: word,
                themeMode: appState.themeMode,
                dismissOnTap: true,
                onDismiss: {
                    spotlightWord = nil
                    if openedFromWidget {
                        widgetOpenedWordId = nil
                    }
                },
                onSwipeForgot: { markPresentedWordForgot($0, openedFromWidget: openedFromWidget) },
                onSwipeMastered: { markPresentedWordMastered($0, openedFromWidget: openedFromWidget) },
                onSwipeBlurry: { markPresentedWordBlurry($0, openedFromWidget: openedFromWidget) }
            )
        }
        #endif
    }

    private func presentSpotlightWordIfAvailable(_ wordId: String?) {
        guard let wordId else {
            return
        }
        guard let word = appState.getWordById(wordId) else {
            appState.spotlightSelectedWordId = nil
            return
        }

        appState.spotlightSelectedWordId = nil
        widgetOpenedWordId = nil
        spotlightWord = word
    }

    private func presentWidgetWordIfAvailable(_ wordId: String?) {
        guard let wordId,
              let word = appState.getWordById(wordId) ?? appState.words.first(where: { $0.id == wordId }) else {
            return
        }

        appState.widgetSelectedWordId = nil
        widgetOpenedWordId = wordId
        spotlightWord = word
    }

    private func markPresentedWordForgot(_ id: String, openedFromWidget: Bool) {
        srsManager.markWordForgot(id, persistDuringInfinitePractice: true)
        refreshWidgetAfterMarking(wordId: id, openedFromWidget: openedFromWidget)
    }

    private func markPresentedWordMastered(_ id: String, openedFromWidget: Bool) {
        srsManager.markWordMastered(id, persistDuringInfinitePractice: true)
        refreshWidgetAfterMarking(wordId: id, openedFromWidget: openedFromWidget)
    }

    private func markPresentedWordBlurry(_ id: String, openedFromWidget: Bool) {
        srsManager.markWordBlurry(id, persistDuringInfinitePractice: true)
        refreshWidgetAfterMarking(wordId: id, openedFromWidget: openedFromWidget)
    }

    private func refreshWidgetAfterMarking(wordId: String, openedFromWidget: Bool) {
        guard openedFromWidget, appState.hasCompletedInitialResourceLoad else { return }
        WidgetDataService.writeWidgetPool(
            from: appState.words,
            language: appState.language,
            level: appState.level,
            memberUnlocked: appState.memberUnlocked,
            excluding: [wordId]
        )
        WidgetCenter.shared.reloadAllTimelines()
        widgetOpenedWordId = nil
    }

    private func advanceDiscover() {
        discoverQueueIndex = 0
    }

    private func markDiscoverWordForgot(_ id: String) {
        let isInfinitePractice = srsManager.isInfinitePracticeActive
        srsManager.markWordForgot(
            id,
            persistDuringInfinitePractice: isInfinitePractice,
            affectsDailyProgress: !isInfinitePractice
        )
        advanceDiscover()
    }

    private func markDiscoverWordMastered(_ id: String) {
        let isInfinitePractice = srsManager.isInfinitePracticeActive
        srsManager.markWordMastered(
            id,
            persistDuringInfinitePractice: isInfinitePractice,
            affectsDailyProgress: !isInfinitePractice
        )
        advanceDiscover()
    }

    private func markDiscoverWordBlurry(_ id: String) {
        let isInfinitePractice = srsManager.isInfinitePracticeActive
        srsManager.markWordBlurry(
            id,
            persistDuringInfinitePractice: isInfinitePractice,
            affectsDailyProgress: !isInfinitePractice
        )
        advanceDiscover()
    }

    private func setExploreGalaxyVisibility(_ visible: Bool, delayReveal: Bool? = nil) {
        pendingGalaxyTabBarRevealTask?.cancel()
        pendingGalaxyTabBarRevealTask = nil

        guard !visible else {
            isGalaxyVisibleInExplore = true
            return
        }

        let shouldDelayReveal = delayReveal ?? (selectedTab == .explore)
        guard shouldDelayReveal else {
            isGalaxyVisibleInExplore = false
            return
        }

        pendingGalaxyTabBarRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: galaxyTabBarRevealDelay)
            guard !Task.isCancelled else { return }
            isGalaxyVisibleInExplore = false
            pendingGalaxyTabBarRevealTask = nil
        }
    }
}

private struct SearchPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let allWords: [SimpleWord]
    let searchIndex: WordSearchIndex

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $isPresented) {
            SearchSheetView(
                isPresented: $isPresented,
                allWords: allWords,
                searchIndex: searchIndex,
                presentationStyle: .fullScreen
            )
        }
        #else
        content.sheet(isPresented: $isPresented) {
            SearchSheetView(
                isPresented: $isPresented,
                allWords: allWords,
                searchIndex: searchIndex,
                presentationStyle: .sheet
            )
        }
        #endif
    }
}

#if os(iOS)
private struct SettingsTabGearAnimationBridge: UIViewRepresentable {
    let settingsIndex: Int
    let spinToken: Int
    let isTabBarHidden: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(settingsIndex: settingsIndex)
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.update(from: uiView, spinToken: spinToken, isTabBarHidden: isTabBarHidden)
    }

    @MainActor
    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.refresh(from: self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            coordinator?.refresh(from: self)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private let settingsIndex: Int
        private weak var tabBar: UITabBar?
        private weak var tapRecognizer: UITapGestureRecognizer?
        private var currentSpinToken = 0
        private var lastAppliedSpinToken = 0
        private var currentTabBarHidden = false
        private var lastAppliedTabBarHidden: Bool?

        init(settingsIndex: Int) {
            self.settingsIndex = settingsIndex
        }

        func refresh(from view: UIView) {
            guard tabBar == nil else { return }
            update(from: view, spinToken: currentSpinToken, isTabBarHidden: currentTabBarHidden)
        }

        func update(from view: UIView, spinToken: Int, isTabBarHidden: Bool) {
            currentSpinToken = spinToken
            currentTabBarHidden = isTabBarHidden

            guard let tabBar = locateTabBar(from: view) else {
                detach()
                return
            }

            if self.tabBar !== tabBar {
                detach()
                self.tabBar = tabBar
                let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTabBarTap(_:)))
                recognizer.cancelsTouchesInView = false
                recognizer.delegate = self
                tabBar.addGestureRecognizer(recognizer)
                tapRecognizer = recognizer
            }

            applyTabBarHiddenIfNeeded(hidden: isTabBarHidden, in: tabBar)

            guard spinToken != lastAppliedSpinToken else { return }
            lastAppliedSpinToken = spinToken
            animateSettingsGear()
        }

        @objc private func handleTabBarTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let tabBar,
                  let index = tabIndex(at: recognizer.location(in: tabBar), in: tabBar),
                  index == settingsIndex else {
                return
            }

            animateSettingsGear()
        }

        private func animateSettingsGear() {
            guard let tabBar,
                  let tabItemView = tabItemView(in: tabBar, index: settingsIndex) else {
                return
            }

            if let imageView = findImageView(in: tabItemView) {
                animateRotation(on: imageView.layer, key: "settingsGearSpin")
                return
            }

            animateRotation(on: tabItemView.layer, key: "settingsGearSpinFallback")
        }

        private func animateRotation(on layer: CALayer, key: String) {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.byValue = Double.pi * 2
            animation.duration = 0.52
            animation.isAdditive = true
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.removeAnimation(forKey: key)
            layer.add(animation, forKey: key)
        }

        private func detach() {
            if let tapRecognizer {
                tapRecognizer.view?.removeGestureRecognizer(tapRecognizer)
            }
            tapRecognizer = nil
            tabBar = nil
            lastAppliedTabBarHidden = nil
        }

        private func applyTabBarHiddenIfNeeded(hidden: Bool, in tabBar: UITabBar) {
            guard let tabBarController = locateTabBarController(from: tabBar) else { return }
            if lastAppliedTabBarHidden == hidden {
                return
            }
            let animate = lastAppliedTabBarHidden != nil
            tabBarController.setTabBarHidden(hidden, animated: animate)
            lastAppliedTabBarHidden = hidden
        }

        private func tabIndex(at point: CGPoint, in tabBar: UITabBar) -> Int? {
            guard let itemCount = tabBar.items?.count,
                  itemCount > 0 else {
                return nil
            }

            let itemWidth = tabBar.bounds.width / CGFloat(itemCount)
            guard itemWidth > 0 else { return nil }

            let rawIndex = Int(point.x / itemWidth)
            return min(max(rawIndex, 0), itemCount - 1)
        }

        private func locateTabBar(from view: UIView) -> UITabBar? {
            if let window = view.window,
               let tabBar = preferredTabBar(in: window) {
                return tabBar
            }

            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }

            for scene in scenes {
                for window in scene.windows.reversed() {
                    if let tabBar = preferredTabBar(in: window) {
                        return tabBar
                    }
                }
            }

            return nil
        }

        private func preferredTabBar(in root: UIView) -> UITabBar? {
            let candidates = findTabBars(in: root)
                .filter { $0.bounds.width > 0 && $0.bounds.height > 0 }

            return candidates.max { lhs, rhs in
                lhs.convert(lhs.bounds, to: nil).maxY < rhs.convert(rhs.bounds, to: nil).maxY
            }
        }

        private func locateTabBarController(from tabBar: UITabBar) -> UITabBarController? {
            var responder: UIResponder? = tabBar
            while let current = responder {
                if let tabBarController = current as? UITabBarController {
                    return tabBarController
                }
                responder = current.next
            }
            return nil
        }

        private func findTabBars(in view: UIView) -> [UITabBar] {
            var result: [UITabBar] = []
            if let tabBar = view as? UITabBar {
                result.append(tabBar)
            }

            for subview in view.subviews {
                result.append(contentsOf: findTabBars(in: subview))
            }

            return result
        }

        private func tabItemView(in tabBar: UITabBar, index: Int) -> UIView? {
            guard let itemCount = tabBar.items?.count,
                  itemCount > 0,
                  index >= 0,
                  index < itemCount else {
                return nil
            }

            let targetX = (CGFloat(index) + 0.5) * tabBar.bounds.width / CGFloat(itemCount)
            let targetPoint = CGPoint(x: targetX, y: tabBar.bounds.midY)

            let candidates = tabBar.subviews.filter {
                !$0.isHidden &&
                $0.alpha > 0.01 &&
                $0.bounds.width > 12 &&
                $0.bounds.height > 12 &&
                $0.bounds.width < tabBar.bounds.width * 0.9
            }

            let containing = candidates.filter { $0.frame.contains(targetPoint) }
            if let best = containing.min(by: { area($0.bounds) < area($1.bounds) }) {
                return best
            }

            return candidates.min(by: { abs($0.frame.midX - targetX) < abs($1.frame.midX - targetX) })
        }

        private func area(_ rect: CGRect) -> CGFloat {
            rect.width * rect.height
        }

        private func findImageView(in view: UIView) -> UIImageView? {
            var imageViews: [UIImageView] = []
            collectImageViews(in: view, into: &imageViews)
            return imageViews.max(by: { area($0.bounds) < area($1.bounds) })
        }

        private func collectImageViews(in view: UIView, into imageViews: inout [UIImageView]) {
            if let imageView = view as? UIImageView,
               imageView.bounds.width > 0,
               imageView.bounds.height > 0 {
                imageViews.append(imageView)
            }

            for subview in view.subviews {
                collectImageViews(in: subview, into: &imageViews)
            }
        }
    }
}

extension SettingsTabGearAnimationBridge.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif

private struct DiscoverScreen: View {
    let words: [SimpleWord]
    @Binding var queueIndex: Int
    let isActiveTab: Bool
    let onGalaxyVisibilityChanged: (Bool) -> Void
    let onSwipeForgot: (String) -> Void
    let onSwipeMastered: (String) -> Void
    let onSwipeBlurry: (String) -> Void
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var srsManager: SRSManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasSeenCardsInSession = false
    @State private var galaxyWords: [SimpleWord] = []
    @State private var isGalaxyVisible = false
    @State private var galaxyPinchLatched = false
    @State private var activeGalaxyTransition: GalaxySelectedCardTransitionRequest? = nil
    @State private var transitionPinnedWord: SimpleWord? = nil
    @State private var pendingGalaxyBackdropDismissTask: Task<Void, Never>? = nil
    @State private var pendingGalaxyQueueCommitTask: Task<Void, Never>? = nil
    @State private var pendingWidgetWriteTask: Task<Void, Never>? = nil
    @State private var pendingInitialDiscoverPreparationTask: Task<Void, Never>? = nil
    @State private var isPreparingInitialDiscoverContent = true
    @State private var pendingAutoInfiniteTask: Task<Void, Never>? = nil
    private let galaxyTargetCount = 22
    private let galaxyActivationCompression: CGFloat = 0.16
    private let galaxyQueueCommitDelay: UInt64 = 90_000_000
    private let galaxyPersistenceDelay: UInt64 = 420_000_000

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var backgroundGradient: LinearGradient {
        AppColors.appBackgroundGradient(themeMode: appState.themeMode, isDarkMode: isDarkMode)
    }

    private var shouldShowHomeWallpaper: Bool {
        appState.themeMode == .steppe
    }

    private var word: SimpleWord? {
        guard !words.isEmpty else { return nil }
        let idx = min(queueIndex, words.count - 1)
        return words[idx]
    }

    private var shouldShowCompletionCelebration: Bool {
        hasSeenCardsInSession && words.isEmpty && srsManager.hasReachedDailyMasteryGoal
    }

    private var presentedWord: SimpleWord? {
        activeGalaxyTransition?.word ?? transitionPinnedWord ?? (!isGalaxyVisible ? word : nil)
    }

    private var nextQueueWord: SimpleWord? {
        guard words.count > queueIndex + 1 else { return nil }
        return words[queueIndex + 1]
    }

    var body: some View {
        ZStack {
            ThemedBackgroundView(
                themeMode: appState.themeMode,
                isDarkMode: isDarkMode,
                showWallpaper: shouldShowHomeWallpaper
            )

            GeometryReader { geo in
                ZStack {
                    if isGalaxyVisible, !galaxyWords.isEmpty {
                        WordGalaxyOverlay(
                            words: galaxyWords,
                            onSelectCard: beginGalaxyTransition,
                            onDismiss: dismissGalaxyBackdrop
                        )
                        .transition(.identity)
                    }

                    if !appState.hasCompletedInitialResourceLoad || isPreparingInitialDiscoverContent {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.08)
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else if let presentedWord {
                        ActiveDiscoverCardHost(
                            word: presentedWord,
                            peekNextWord: (activeGalaxyTransition == nil && transitionPinnedWord == nil) ? nextQueueWord : nil,
                            transitionRequest: activeGalaxyTransition,
                            containerSize: geo.size,
                            allowsInteractions: activeGalaxyTransition == nil && transitionPinnedWord == nil,
                            isActiveTab: isActiveTab,
                            onSwipeForgot: {
                                onSwipeForgot($0)
                                finishGalaxyTransition()
                            },
                            onSwipeMastered: {
                                onSwipeMastered($0)
                                finishGalaxyTransition()
                            },
                            onSwipeBlurry: {
                                onSwipeBlurry($0)
                                finishGalaxyTransition()
                            },
                            onTransitionComplete: completeGalaxyTransition
                        )
                    } else if !isGalaxyVisible, shouldShowCompletionCelebration {
                        DeckCompletionCelebrationView()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else if !isGalaxyVisible {
                        Group {
                            if srsManager.todayStudyState == .completed {
                                DiscoverEmptyStateView(
                                    title: appState.localized("Today's goal complete", "今日目标已完成", "आज का लक्ष्य पूरा"),
                                    subtitle: appState.localized(
                                        "You've finished your learning goal for today.",
                                        "你今天的学习目标已经完成。",
                                        "आपने आज का सीखने का लक्ष्य पूरा कर लिया है।"
                                    )
                                )
                            } else {
                                DiscoverEmptyStateView(
                                    title: appState.localized(
                                        "No eligible cards at this level",
                                        "当前等级暂无可发卡",
                                        "इस स्तर पर अभी कोई कार्ड उपलब्ध नहीं"
                                    ),
                                    subtitle: appState.localized(
                                        "Switch level or come back when reviews are due.",
                                        "可以切换等级，或等待到期复习后再来。",
                                        "लेवल बदलें या समीक्षा समय आने पर वापस आएं。"
                                    )
                                )
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.26), value: words.isEmpty)
                #if os(iOS)
                .background(
                    ExplorePinchGestureBridge(isEnabled: isActiveTab && word != nil && !isGalaxyVisible && activeGalaxyTransition == nil) { event in
                        handleGalaxyPinch(event, containerFrame: geo.frame(in: .global))
                    }
                    .frame(width: 0, height: 0)
                )
                #endif
            }
            .padding(.horizontal, 20)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            if appState.hasCompletedInitialResourceLoad {
                prepareInitialDiscoverContent()
                scheduleWidgetDataWrite()
            }
            if !words.isEmpty {
                hasSeenCardsInSession = true
            }
        }
        .onChange(of: words.map(\.id).sorted()) { _, ids in
            if !ids.isEmpty {
                hasSeenCardsInSession = true
            }
            scheduleWidgetDataWrite()
        }
        .onChange(of: word?.id) { _, newWordId in
            if activeGalaxyTransition == nil, transitionPinnedWord?.id == newWordId {
                transitionPinnedWord = nil
            }
        }
        .onChange(of: appState.level) { _, _ in
            scheduleWidgetDataWrite()
        }
        .onChange(of: appState.memberUnlocked) { _, _ in
            scheduleWidgetDataWrite()
        }
        .onChange(of: appState.hasCompletedInitialResourceLoad) { _, loaded in
            guard loaded else {
                isPreparingInitialDiscoverContent = true
                return
            }
            prepareInitialDiscoverContent()
            scheduleWidgetDataWrite(delayNanoseconds: 500_000_000)
        }
        .onChange(of: isActiveTab) { _, active in
            guard !active else { return }
            finishGalaxyTransition()
            dismissGalaxyBackdrop()
            transitionPinnedWord = nil
        }
        .onChange(of: shouldShowCompletionCelebration) { _, showing in
            if showing {
                scheduleAutoInfinitePractice()
            } else {
                pendingAutoInfiniteTask?.cancel()
                pendingAutoInfiniteTask = nil
            }
        }
        .onDisappear {
            pendingAutoInfiniteTask?.cancel()
            pendingAutoInfiniteTask = nil
        }
    }

    private func scheduleAutoInfinitePractice() {
        pendingAutoInfiniteTask?.cancel()
        pendingAutoInfiniteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            srsManager.completeDailyGoalAndEnterInfinitePractice()
            pendingAutoInfiniteTask = nil
        }
    }

    private func scheduleWidgetDataWrite(delayNanoseconds: UInt64 = 250_000_000) {
        pendingWidgetWriteTask?.cancel()
        pendingWidgetWriteTask = Task { @MainActor in
            var nextDelay = delayNanoseconds
            while !Task.isCancelled {
                if nextDelay > 0 {
                    try? await Task.sleep(nanoseconds: nextDelay)
                    guard !Task.isCancelled else { return }
                    nextDelay = 0
                }
                guard appState.hasCompletedInitialResourceLoad else { return }
                guard !isPreparingInitialDiscoverContent,
                      !isGalaxyVisible,
                      activeGalaxyTransition == nil else {
                    nextDelay = 350_000_000
                    continue
                }
                guard !Task.isCancelled else { return }
                writeWidgetData()
                pendingWidgetWriteTask = nil
                return
            }
        }
    }

    private func prepareInitialDiscoverContent() {
        isPreparingInitialDiscoverContent = true
        pendingInitialDiscoverPreparationTask?.cancel()
        pendingInitialDiscoverPreparationTask = Task { @MainActor in
            srsManager.prepareDiscoverQueueForDisplay()

            for _ in 0..<4 {
                if isDiscoverContentReadyForDisplay() {
                    break
                }
                await Task.yield()
                srsManager.ensureLearningQueueReady()
            }

            guard !Task.isCancelled else { return }
            isPreparingInitialDiscoverContent = false
            pendingInitialDiscoverPreparationTask = nil
        }
    }

    private func isDiscoverContentReadyForDisplay() -> Bool {
        !srsManager.getLearningQueueWordsSnapshot().isEmpty || srsManager.todayStudyState != .inProgress
    }

    private func writeWidgetData() {
        guard appState.hasCompletedInitialResourceLoad else { return }
        WidgetDataService.writeWidgetPool(
            from: appState.words,
            language: appState.language,
            level: appState.level,
            memberUnlocked: appState.memberUnlocked
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func buildGalaxyWords(excluding currentWordId: String) -> [SimpleWord] {
        let level = appState.level
        let levelWords = level == "All"
            ? appState.words
            : appState.words.filter { $0.level == level }
        let excludedWordIds = srsManager.forgotWordIds
            .union(srsManager.masteredWordIds)
            .union(srsManager.blurryWordIds)
        let candidates = levelWords.filter { $0.id != currentWordId && !excludedWordIds.contains($0.id) }
        guard !candidates.isEmpty else { return [] }
        if candidates.count >= galaxyTargetCount {
            return Array(candidates.shuffled().prefix(galaxyTargetCount))
        }
        var result: [SimpleWord] = []
        result.reserveCapacity(galaxyTargetCount)
        while result.count < galaxyTargetCount {
            result += candidates.shuffled()
        }
        return Array(result.prefix(galaxyTargetCount))
    }

    private func beginGalaxyTransition(_ request: GalaxySelectedCardTransitionRequest) {
        cancelPendingGalaxySettleTasks()
        transitionPinnedWord = request.word
        activeGalaxyTransition = request
    }

    private func completeGalaxyTransition() {
        let selectedWordId = activeGalaxyTransition?.word.id ?? transitionPinnedWord?.id
        scheduleGalaxyBackdropDismiss()
        guard let selectedWordId else { return }

        pendingGalaxyQueueCommitTask?.cancel()
        pendingGalaxyQueueCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: galaxyQueueCommitDelay)
            guard !Task.isCancelled else { return }
            srsManager.promoteWordToLearningQueueFront(selectedWordId, persist: false)
            queueIndex = 0
            if word?.id == selectedWordId {
                transitionPinnedWord = nil
            }
            srsManager.scheduleLearningStateSave(delayNanoseconds: galaxyPersistenceDelay)
            pendingGalaxyQueueCommitTask = nil
        }
    }

    private func finishGalaxyTransition() {
        cancelPendingGalaxySettleTasks()
        activeGalaxyTransition = nil
        if transitionPinnedWord?.id == word?.id || !isGalaxyVisible {
            transitionPinnedWord = nil
        }
    }

    private func scheduleGalaxyBackdropDismiss() {
        pendingGalaxyBackdropDismissTask?.cancel()
        pendingGalaxyBackdropDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            dismissGalaxyBackdrop()
            pendingGalaxyBackdropDismissTask = nil
        }
    }

    private func cancelPendingGalaxySettleTasks() {
        pendingGalaxyBackdropDismissTask?.cancel()
        pendingGalaxyBackdropDismissTask = nil
        pendingGalaxyQueueCommitTask?.cancel()
        pendingGalaxyQueueCommitTask = nil
    }

    private func dismissGalaxyBackdrop() {
        activeGalaxyTransition = nil
        isGalaxyVisible = false
        onGalaxyVisibilityChanged(false)
        galaxyPinchLatched = false
        galaxyWords = []
    }

    #if os(iOS)
    private func handleGalaxyPinch(_ event: ExplorePinchEvent, containerFrame: CGRect) {
        switch event.state {
        case .began:
            galaxyPinchLatched = false
        case .changed:
            guard !galaxyPinchLatched,
                  !isGalaxyVisible,
                  activeGalaxyTransition == nil,
                  appState.hasCompletedInitialResourceLoad,
                  isActiveTab,
                  let word,
                  containerFrame.contains(event.location) else {
                return
            }

            let compression = max(0, 1 - event.scale)
            guard compression >= galaxyActivationCompression else { return }
            let generatedWords = buildGalaxyWords(excluding: word.id)
            guard !generatedWords.isEmpty else { return }

            galaxyPinchLatched = true
            galaxyWords = generatedWords
            isGalaxyVisible = true
            onGalaxyVisibilityChanged(true)
        case .ended, .cancelled, .failed:
            galaxyPinchLatched = false
        default:
            break
        }
    }
    #endif
}

private struct WordGalaxyOverlay: View {
    let words: [SimpleWord]
    let onSelectCard: (GalaxySelectedCardTransitionRequest) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var revealProgress: CGFloat = 0
    @State private var animationStart = Date()
    @State private var isDismissing = false
    @State private var canDismissByTap = false
    @State private var orbitDragOffset = 0.0
    @State private var previousDragTranslationX: CGFloat = 0
    @State private var touchDownDate: Date? = nil
    @State private var galaxyScale: CGFloat = 1
    @State private var pinchStartScale: CGFloat = 1
    @State private var isPinching = false
    @State private var selectedCardIndex: Int? = nil
    @State private var selectionAnimationStartTime: Date? = nil
    @State private var spinDragDelta: Double = 0
    @State private var isDealing = true

    private let orbitSpeed: Double = 36
    private let pileAngle: Double = .pi * 0.65
    private let dealDuration: Double = 0.56
    private let dealTapUnlockDelay: Double = 0.36
    private let dealStaggerPerCard: Double = 0.012
    private let compressedFanOrbitSteps: Double = 3.0
    private let compressedFanPower: Double = 0.82
    private let depthZSwitchProgress: Double = 0.42
    private let galaxyScaleRange: ClosedRange<CGFloat> = 0.45...1.90
    private let frontFacingAngle: Double = -.pi / 2.0
    private let selectionTransitionDuration: Double = 0.48
    private let innerDustCount = 9
    private let innerDustRiseDistance: CGFloat = 88
    private let innerDustCycleDuration: Double = 6

    private var innerDustColor: Color {
        Color(red: 0.19, green: 0.73, blue: 0.46)
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                galaxyFrame(context: context, geo: geo)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isPinching, selectedCardIndex == nil, selectionAnimationStartTime == nil, !isDealing else { return }
                        if touchDownDate == nil {
                            touchDownDate = Date()
                        }
                        let delta = value.translation.width - previousDragTranslationX
                        previousDragTranslationX = value.translation.width
                        orbitDragOffset += Double(delta) / 80.0
                        FeedbackService.wheelSpinTick(deltaX: delta)
                    }
                    .onEnded { value in
                        guard !isPinching, !isDealing else {
                            previousDragTranslationX = 0
                            return
                        }
                        FeedbackService.wheelSpinEnded()
                        let totalDrag = abs(value.translation.width) + abs(value.translation.height)
                        let projectedDeltaX = value.predictedEndTranslation.width - value.translation.width
                        let projectedDeltaY = value.predictedEndTranslation.height - value.translation.height
                        let projectedDrag = abs(projectedDeltaX) + abs(projectedDeltaY)
                        let isTap = totalDrag < 10 && projectedDrag < 12 && canDismissByTap
                        if isTap {
                            let elapsed = (touchDownDate ?? Date()).timeIntervalSince(animationStart)
                            let cards = projectedCards(
                                elapsed: elapsed
                            )
                            if let hitCard = hitTestCard(
                                at: value.location,
                                in: geo.size,
                                cards: cards
                            ) {
                                selectCard(hitCard)
                            } else {
                                dismiss()
                            }
                        } else if selectedCardIndex == nil {
                            applyInertia(using: value)
                        }
                        previousDragTranslationX = 0
                        if selectedCardIndex == nil, let td = touchDownDate {
                            let pauseDuration = Date().timeIntervalSince(td)
                            animationStart = animationStart.addingTimeInterval(pauseDuration)
                            touchDownDate = nil
                        }
                    }
            )
            #if os(iOS)
            .background(
                ExplorePinchGestureBridge(isEnabled: selectedCardIndex == nil && selectionAnimationStartTime == nil) { event in
                    handleScalePinch(event)
                }
                .frame(width: 0, height: 0)
            )
            #endif
            .onAppear {
                animationStart = Date()
                canDismissByTap = false
                galaxyScale = 1
                pinchStartScale = 1
                isPinching = false
                selectedCardIndex = nil
                selectionAnimationStartTime = nil
                spinDragDelta = 0
                isDealing = true
                withAnimation(.linear(duration: dealDuration)) {
                    revealProgress = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + dealDuration) {
                    guard !isDismissing else { return }
                    isDealing = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + dealTapUnlockDelay) {
                    guard !isDismissing else { return }
                    canDismissByTap = true
                }
            }
        }
    }

    @ViewBuilder
    private func galaxyFrame(
        context: TimelineViewDefaultContext,
        geo: GeometryProxy
    ) -> some View {
        let referenceDate = isPinching ? context.date : (touchDownDate ?? context.date)
        let elapsed = referenceDate.timeIntervalSince(animationStart)
        let spinT: Double = {
            guard let selectionAnimationStartTime else { return 0 }
            return min(1.0, context.date.timeIntervalSince(selectionAnimationStartTime) / selectionTransitionDuration)
        }()
        let spinEased = galaxySmoothStep(spinT)
        let spinExtra = spinDragDelta * spinEased
        let selectionProgress: Double = {
            guard let selectionAnimationStartTime else { return 0 }
            return min(1.0, context.date.timeIntervalSince(selectionAnimationStartTime) / selectionTransitionDuration)
        }()
        let cards = projectedCards(elapsed: elapsed, extraDragOffset: spinExtra)
        let visibleCards = cards.filter { $0.cardIndex != selectedCardIndex }
        let galaxyBackdropOpacity = max(0.0, 1.0 - galaxySmoothStep(selectionProgress))

        ZStack {
            if galaxyBackdropOpacity > 0.001 {
                if !reduceMotion {
                    innerRingDust(
                        elapsed: elapsed,
                        orbitOffset: orbitDragOffset + spinExtra
                    )
                        .opacity(galaxyBackdropOpacity)
                }
                ForEach(visibleCards) { card in
                    renderedGalaxyCard(card)
                        .opacity(galaxyBackdropOpacity)
                }
            }
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }

    @ViewBuilder
    private func innerRingDust(elapsed: TimeInterval, orbitOffset: Double) -> some View {
        let clampedElapsed = max(0, elapsed)
        let isDarkMode = colorScheme == .dark
        let minVisibleOpacity = isDarkMode ? 0.0 : 0.34

        ForEach(0..<innerDustCount, id: \.self) { index in
            let phase = (clampedElapsed / innerDustCycleDuration + Double(index) * 0.173).truncatingRemainder(dividingBy: 1.0)
            let opacityCurve = sin(.pi * phase)
            let angle = orbitOffset * 0.62 + Double(index) * (2.0 * .pi / Double(innerDustCount))
            let radiusX = GalaxyOrbit.radius * 0.54 * Double(galaxyScale)
            let radiusY = GalaxyOrbit.radius * 0.19 * Double(galaxyScale)
            let driftX = sin(phase * 2.0 * .pi + Double(index) * 0.8) * 6.0
            let riseY = Double(innerDustRiseDistance * galaxyScale) * phase
            let glowPulse = 0.74 + 0.26 * sin(clampedElapsed * 0.8 + Double(index))
            let dynamicOpacity = opacityCurve * glowPulse * Double(revealProgress)
            let opacity = min(1.0, max(minVisibleOpacity * Double(revealProgress), dynamicOpacity))

            if opacity > 0.001 {
                ZStack {
                    if isDarkMode {
                        Circle()
                            .fill(innerDustColor.opacity(0.28))
                            .frame(width: 9.6, height: 9.6)
                            .blur(radius: 1.2)
                        Circle()
                            .fill(innerDustColor.opacity(0.38))
                            .frame(width: 6.8, height: 6.8)
                            .blur(radius: 0.45)
                    }
                    Circle()
                        .fill(innerDustColor)
                        .frame(width: 2.6, height: 2.6)
                }
                .opacity(opacity)
                .scaleEffect(0.92 + CGFloat(phase) * 0.16)
                .offset(
                    x: cos(angle) * radiusX + driftX,
                    y: sin(angle) * radiusY - riseY
                )
                .blendMode(isDarkMode ? .plusLighter : .normal)
                .shadow(color: innerDustColor.opacity(0.34), radius: isDarkMode ? 2.8 : 0, x: 0, y: 0)
                .allowsHitTesting(false)
            }
        }
    }

    private func renderedGalaxyCard(_ card: ProjectedGalaxyCard) -> some View {
        let state = orbitGalaxyCardState(for: card)
        let materialEnabled = selectionAnimationStartTime == nil
        return GalaxyWordCard(word: card.word, materialEnabled: materialEnabled)
            .rotation3DEffect(
                .degrees(state.tiltY),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0
            )
            .rotationEffect(.degrees(state.tiltZ))
            .scaleEffect(state.scale)
            .offset(state.offset)
            .opacity(state.opacity)
            .blur(radius: state.blur)
            .zIndex(card.zOrder)
    }

    private func selectCard(_ hitCard: ProjectedGalaxyCard) {
        guard !isDismissing, selectedCardIndex == nil, selectionAnimationStartTime == nil else { return }
        selectedCardIndex = hitCard.cardIndex
        canDismissByTap = false

        var deltaAngle = frontFacingAngle - hitCard.angle
        deltaAngle = deltaAngle.truncatingRemainder(dividingBy: 2.0 * .pi)
        if deltaAngle > .pi { deltaAngle -= 2.0 * .pi }
        if deltaAngle < -.pi { deltaAngle += 2.0 * .pi }
        spinDragDelta = deltaAngle * 180.0 / (orbitSpeed * .pi)
        selectionAnimationStartTime = Date()
        onSelectCard(
            GalaxySelectedCardTransitionRequest(
                word: hitCard.word,
                sourceCardWidth: 66,
                galaxyScale: galaxyScale,
                rollStartAngle: hitCard.angle,
                rollEndAngle: hitCard.angle + deltaAngle
            )
        )
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        withAnimation(.easeInOut(duration: 0.24)) {
            revealProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            onDismiss()
        }
    }

    #if os(iOS)
    private func handleScalePinch(_ event: ExplorePinchEvent) {
        guard !isDismissing, selectedCardIndex == nil, selectionAnimationStartTime == nil else { return }
        if event.state == .began || event.state == .changed {
            isPinching = true
            if let td = touchDownDate {
                let pauseDuration = Date().timeIntervalSince(td)
                animationStart = animationStart.addingTimeInterval(pauseDuration)
                touchDownDate = nil
            }
        }
        switch event.state {
        case .began:
            pinchStartScale = galaxyScale
            previousDragTranslationX = 0
        case .changed:
            let nextScale = pinchStartScale * event.scale
            galaxyScale = min(max(nextScale, galaxyScaleRange.lowerBound), galaxyScaleRange.upperBound)
        case .ended, .cancelled, .failed:
            isPinching = false
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                galaxyScale = 1
            }
            pinchStartScale = 1
        default:
            break
        }
    }
    #endif

    private func applyInertia(using value: DragGesture.Value) {
        let projectedDeltaX = value.predictedEndTranslation.width - value.translation.width
        let velocityTurns = Double(projectedDeltaX) / 220.0
        let distanceTurns = Double(value.translation.width) / 900.0
        let inertiaTurns = min(max(velocityTurns + distanceTurns, -4.5), 4.5)
        guard abs(inertiaTurns) >= 0.05 else { return }

        let duration = min(1.8, max(0.45, 0.55 + abs(inertiaTurns) * 0.25))
        withAnimation(.timingCurve(0.15, 0.90, 0.22, 1.00, duration: duration)) {
            orbitDragOffset += inertiaTurns
        }
    }

    private func orbitGalaxyCardState(for card: ProjectedGalaxyCard) -> SelectedGalaxyCardState {
        SelectedGalaxyCardState(
            offset: CGSize(
                width: card.offset.width * galaxyScale,
                height: card.offset.height * galaxyScale
            ),
            scale: CGFloat(card.scale) * galaxyScale,
            tiltY: card.cardTiltY,
            tiltZ: 15,
            opacity: card.opacity,
            blur: CGFloat(card.blur)
        )
    }

    private func hitTestCard(
        at location: CGPoint,
        in size: CGSize,
        cards: [ProjectedGalaxyCard]
    ) -> ProjectedGalaxyCard? {
        cards
            .sorted { $0.depth < $1.depth }
            .first { card in
                let scale = CGFloat(card.scale) * galaxyScale
                let side = 68.0 * scale * 1.12
                let frame = CGRect(
                    x: size.width / 2 + card.offset.width * galaxyScale - side / 2,
                    y: size.height / 2 + card.offset.height * galaxyScale - side / 2,
                    width: side,
                    height: side
                )
                return frame.contains(location)
            }
    }

    private func projectedCards(
        elapsed: TimeInterval,
        extraDragOffset: Double = 0
    ) -> [ProjectedGalaxyCard] {
        guard !words.isEmpty else { return [] }

        let visibilityProgress = max(0.0001, Double(revealProgress))
        let count = words.count
        let clampedVisibilityProgress = min(1.0, max(0.0, visibilityProgress))
        let orbitStep = 2.0 * .pi / Double(count)
        let dealProgress = min(1.0, max(0.0, elapsed / dealDuration))

        // Orbit rotation starts from frame 1 (no delay)
        let orbitRad = (elapsed + orbitDragOffset + extraDragOffset) * orbitSpeed * .pi / 180.0

        let compressedSpan = compressedFanOrbitSteps * orbitStep
        let maxSlot = Double(max(count - 1, 1))

        var results: [ProjectedGalaxyCard] = []
        results.reserveCapacity(count)

        for (index, word) in words.enumerated() {
            let visualRank = index
            let releaseRank = index
            let orbitRank = count - 1 - index
            let slotFraction = Double(visualRank) / maxSlot

            let localDelay = Double(releaseRank) * dealStaggerPerCard / dealDuration
            let rawLocal = min(1.0, max(0.0, (dealProgress - localDelay) / max(1.0 - localDelay, 0.001)))
            let openProgress = galaxySmoothStep(rawLocal)

            let compressedOffset = compressedSpan / 2 - pow(slotFraction, compressedFanPower) * compressedSpan
            let finalOffset = Double(orbitRank) * orbitStep

            let angle = pileAngle + orbitRad + galaxyLerp(compressedOffset, finalOffset, openProgress)
            let p = GalaxyOrbit.project(angle: angle)

            let targetScale = 0.5 + 0.5 * p.depthScale
            let scale = targetScale * clampedVisibilityProgress + (1 - clampedVisibilityProgress) * 0.80
            let targetOpacity = min(1.0, 0.25 + 0.75 * p.depthScale)
            let opacity = targetOpacity * clampedVisibilityProgress + (1 - clampedVisibilityProgress) * 0.90
            let blur = max(0.0, (1.0 - p.depthScale) * 3.0)

            let zOrder = openProgress < depthZSwitchProgress ? Double(count - releaseRank) : -p.wz

            results.append(ProjectedGalaxyCard(
                id: "\(word.id)-\(index)",
                word: word,
                cardIndex: index,
                angle: angle,
                offset: CGSize(width: p.screenX, height: p.screenY),
                scale: scale,
                opacity: opacity,
                blur: blur,
                depth: p.wz,
                cardTiltY: p.cardTiltY,
                zOrder: zOrder
            ))
        }

        return results
    }
}

private struct GalaxySelectedCardTransitionRequest {
    let word: SimpleWord
    let sourceCardWidth: CGFloat
    let galaxyScale: CGFloat
    let rollStartAngle: Double
    let rollEndAngle: Double
}

private func galaxySmoothStep(_ progress: Double) -> Double {
    let t = min(1.0, max(0.0, progress))
    return t * t * (3 - 2 * t)
}

private func galaxyLerp(_ start: CGFloat, _ end: CGFloat, _ progress: Double) -> CGFloat {
    start + (end - start) * CGFloat(progress)
}

private func galaxyLerp(_ start: Double, _ end: Double, _ progress: Double) -> Double {
    start + (end - start) * progress
}

private enum GalaxyOrbit {
    static let radius: Double = 135
    static let tiltX: Double = 18
    static let tiltZ: Double = 17
    static let camera: Double = 750

    // Precomputed Rz · Rx rotation matrix (localY = 0)
    private static let rxRad = tiltX * .pi / 180.0
    private static let rzRad = tiltZ * .pi / 180.0
    static let m00 = cos(rzRad)
    static let m02 = sin(rzRad) * sin(rxRad)
    static let m10 = sin(rzRad)
    static let m12 = -cos(rzRad) * sin(rxRad)
    static let m22 = cos(rxRad)

    struct Projection {
        let screenX: Double
        let screenY: Double
        let depthScale: Double
        let cardTiltY: Double
        let wz: Double
    }

    static func project(angle: Double) -> Projection {
        let cosA = cos(angle), sinA = sin(angle)
        let lx = cosA * radius
        let lz = sinA * radius
        let wx = m00 * lx + m02 * lz
        let wy = m10 * lx + m12 * lz
        let wz = m22 * lz
        let depthScale = camera / (camera + wz)
        return Projection(
            screenX: wx * depthScale,
            screenY: wy * depthScale,
            depthScale: depthScale,
            cardTiltY: -asin(sin(angle)) * 180.0 / .pi,
            wz: wz
        )
    }
}

private func galaxyAccentBorder(isDarkMode: Bool) -> LinearGradient {
    LinearGradient(
        colors: [
            Color(red: 0.28, green: 0.95, blue: 0.56).opacity(isDarkMode ? 0.82 : 0.62),
            Color(red: 0.16, green: 0.78, blue: 0.46).opacity(isDarkMode ? 0.72 : 0.52)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private enum DiscoverCardLayout {
    static let horizontalInset: CGFloat = 20
    static let horizontalInsetTotal: CGFloat = horizontalInset * 2
    private static let cardBodyVerticalPaddingTotal: CGFloat = 48

    static func contentWidth(forScreenWidth width: CGFloat) -> CGFloat {
        max(width - horizontalInsetTotal, 0)
    }

    static func cardHeight(forCardWidth width: CGFloat) -> CGFloat {
        max(width - cardBodyVerticalPaddingTotal, 0)
    }

    static func restingCardYOffset(containerHeight: CGFloat) -> CGFloat {
        -min(56, max(36, containerHeight * 0.06))
    }
}

private struct ActiveDiscoverCardHost: View {
    let word: SimpleWord
    let peekNextWord: SimpleWord?
    let transitionRequest: GalaxySelectedCardTransitionRequest?
    let containerSize: CGSize
    let allowsInteractions: Bool
    let isActiveTab: Bool
    let onSwipeForgot: (String) -> Void
    let onSwipeMastered: (String) -> Void
    let onSwipeBlurry: (String) -> Void
    let onTransitionComplete: () -> Void

    @State private var animationStart = Date()
    @State private var hasCompletedTransition = false
    @State private var swipeInOffsetY: CGFloat = 0
    @State private var swipeInScale: CGFloat = 1.0
    @State private var swipeInOpacity: Double = 1.0
    @State private var topCardDrag: CGSize = .zero

    private let transitionDuration: Double = 0.48
    private var restingCardYOffset: CGFloat {
        DiscoverCardLayout.restingCardYOffset(containerHeight: containerSize.height)
    }
    private var restingCardContentHeight: CGFloat {
        DiscoverCardLayout.cardHeight(forCardWidth: containerSize.width)
    }

    var body: some View {
        Group {
            if let transitionRequest {
                TimelineView(.animation) { context in
                    let progress = min(1.0, context.date.timeIntervalSince(animationStart) / transitionDuration)
                    ZStack {
                        renderedCard(progress: progress, transitionRequest: transitionRequest)
                        if progress >= 1.0, !hasCompletedTransition {
                            Color.clear
                                .frame(width: 0, height: 0)
                                .onAppear {
                                    hasCompletedTransition = true
                                    onTransitionComplete()
                                }
                        }
                    }
                }
            } else {
                renderedCard(progress: 1, transitionRequest: nil)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .onAppear {
            if transitionRequest != nil {
                animationStart = Date()
                hasCompletedTransition = false
            }
        }
        .onChange(of: transitionRequest?.word.id) { oldValue, newValue in
            guard newValue != oldValue, newValue != nil else { return }
            animationStart = Date()
            hasCompletedTransition = false
        }
        .onChange(of: word.id) { _, _ in
            guard transitionRequest == nil else { return }
            let dragMagnitude = sqrt(topCardDrag.width * topCardDrag.width + topCardDrag.height * topCardDrag.height)
            let wasFullyRevealed = dragMagnitude / 150.0 >= 0.95
            topCardDrag = .zero
            guard !wasFullyRevealed else { return }
            swipeInOffsetY = 44
            swipeInScale = 0.94
            swipeInOpacity = 0
            withAnimation(.spring(response: 0.38, dampingFraction: 0.70)) {
                swipeInOffsetY = 0
                swipeInScale = 1.0
            }
            withAnimation(.easeIn(duration: 0.7)) {
                swipeInOpacity = 1.0
            }
        }
    }

    @ViewBuilder
    private func renderedCard(progress: Double, transitionRequest: GalaxySelectedCardTransitionRequest?) -> some View {
        let detailProgress = transitionDetailProgress(progress: progress, transitionRequest: transitionRequest)
        let isTransitioning = transitionRequest != nil
        let glowStrength = isTransitioning ? min(1.0, detailProgress) : 1.0
        let cardContentOpacity = isTransitioning ? 1.0 : swipeInOpacity
        let interactionEnabled = !isTransitioning && allowsInteractions
        let cardYOffset = restingCardYOffset * CGFloat(detailProgress)
        let state: SelectedGalaxyCardState = transitionRequest.map {
            transitionRenderState(for: $0, targetCardWidth: containerSize.width, progress: progress)
        } ?? SelectedGalaxyCardState(offset: .zero, scale: 1, tiltY: 0, tiltZ: 0, opacity: 1, blur: 0)

        let showPeekUnderlay = transitionRequest == nil && peekNextWord != nil
        let dragMagnitude = sqrt(topCardDrag.width * topCardDrag.width + topCardDrag.height * topCardDrag.height)
        let t = min(1.0, dragMagnitude / 150.0)
        let peekProgress = t * t  // scale + offset + opacity：二次，中期到位

        ZStack {
            if showPeekUnderlay, let peek = peekNextWord {
                DiscoverCard(
                    word: peek,
                    screenWidth: containerSize.width,
                    cardWidth: containerSize.width,
                    cardHeight: restingCardContentHeight,
                    isActiveTab: false,
                    detailProgress: 1,
                    glowStrength: 0.32,
                    contentOpacity: 1,
                    interactionsEnabled: false,
                    onSwipeForgot: { _ in },
                    onSwipeMastered: { _ in },
                    onSwipeBlurry: { _ in }
                )
                .id(peek.id)
                .scaleEffect(0.94 + 0.06 * peekProgress)
                .offset(y: 44.0 * (1.0 - peekProgress))
                .opacity(Double(peekProgress))
                .allowsHitTesting(false)
            }

            DiscoverCard(
                word: word,
                screenWidth: containerSize.width,
                cardWidth: containerSize.width,
                cardHeight: restingCardContentHeight,
                isActiveTab: isActiveTab && interactionEnabled,
                detailProgress: detailProgress,
                glowStrength: glowStrength,
                contentOpacity: cardContentOpacity,
                interactionsEnabled: interactionEnabled,
                onSwipeForgot: onSwipeForgot,
                onSwipeMastered: onSwipeMastered,
                onSwipeBlurry: onSwipeBlurry,
                onDragChanged: { offset in
                    if offset.width == 0 && offset.height == 0 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            topCardDrag = .zero
                        }
                    } else {
                        topCardDrag = offset
                    }
                }
            )
            .id(word.id)
            .offset(y: swipeInOffsetY)
            .scaleEffect(swipeInScale)
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .position(x: containerSize.width / 2, y: containerSize.height / 2 + cardYOffset)
        .allowsHitTesting(!isTransitioning)
        .rotation3DEffect(
            .degrees(state.tiltY),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0
        )
        .rotationEffect(.degrees(state.tiltZ))
        .scaleEffect(state.scale)
        .offset(state.offset)
        .opacity(state.opacity)
        .modifier(ConditionalBlur(radius: state.blur))
    }

    private func transitionDetailProgress(progress: Double, transitionRequest: GalaxySelectedCardTransitionRequest?) -> Double {
        guard transitionRequest != nil else { return 1.0 }
        let t = min(1.0, max(0.0, (progress - 0.02) / 0.40))
        return galaxySmoothStep(t)
    }

    private func transitionRenderState(
        for request: GalaxySelectedCardTransitionRequest,
        targetCardWidth: CGFloat,
        progress: Double
    ) -> SelectedGalaxyCardState {
        let eased = galaxySmoothStep(progress)
        let angle = galaxyLerp(request.rollStartAngle, request.rollEndAngle, eased)
        let base = orbitState(angle: angle, galaxyScale: request.galaxyScale)
        let currentWidth = request.sourceCardWidth * base.scale
        let settleT = galaxySmoothStep(min(1.0, max(0.0, (progress - 0.10) / 0.90)))
        let scaleT = galaxySmoothStep(min(1.0, max(0.0, (progress - 0.04) / 0.96)))
        let blurT = galaxySmoothStep(min(1.0, max(0.0, progress * 2.2)))

        return SelectedGalaxyCardState(
            offset: CGSize(
                width: galaxyLerp(base.offset.width, 0, settleT),
                height: galaxyLerp(base.offset.height, 0, settleT)
            ),
            scale: galaxyLerp(currentWidth / max(targetCardWidth, 1), 1, scaleT),
            tiltY: galaxyLerp(base.tiltY, 0, settleT),
            tiltZ: galaxyLerp(base.tiltZ, 0, settleT),
            opacity: galaxyLerp(base.opacity, 1, settleT),
            blur: galaxyLerp(base.blur, 0, blurT)
        )
    }

    private func orbitState(angle: Double, galaxyScale: CGFloat) -> SelectedGalaxyCardState {
        let p = GalaxyOrbit.project(angle: angle)
        let scale = (0.5 + 0.5 * p.depthScale) * galaxyScale
        let opacity = min(1.0, 0.25 + 0.75 * p.depthScale)
        let blur = max(0.0, (1.0 - p.depthScale) * 3.0)

        return SelectedGalaxyCardState(
            offset: CGSize(width: p.screenX * galaxyScale, height: p.screenY * galaxyScale),
            scale: CGFloat(scale),
            tiltY: p.cardTiltY,
            tiltZ: 15,
            opacity: opacity,
            blur: CGFloat(blur)
        )
    }
}

private struct SelectedGalaxyCardState {
    let offset: CGSize
    let scale: CGFloat
    let tiltY: Double
    let tiltZ: Double
    let opacity: Double
    let blur: CGFloat
}

private struct ProjectedGalaxyCard: Identifiable {
    let id: String
    let word: SimpleWord
    let cardIndex: Int
    let angle: Double
    let offset: CGSize
    let scale: Double
    let opacity: Double
    let blur: Double
    let depth: Double
    let cardTiltY: Double
    let zOrder: Double
}

private struct SelectedGalaxyCardAnimation {
    let word: SimpleWord
    let cardWidth: CGFloat
    let cardHeight: CGFloat
}

private struct GalaxyWordCard: View {
    let word: SimpleWord
    var materialEnabled: Bool = true
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    init(word: SimpleWord, materialEnabled: Bool = true) {
        self.word = word
        self.materialEnabled = materialEnabled
    }

    private enum CardFontWeight {
        case regular
        case medium
        case semibold
        case bold
    }

    private var title: String {
        let display = word.displayWord.trimmingCharacters(in: .whitespacesAndNewlines)
        return display.isEmpty ? word.word : display
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var titleFont: Font {
        switch appState.cardFontStyle {
        case .sfPro: return .system(size: 9.5, weight: .bold, design: .default)
        case .sfRounded: return .system(size: 9.5, weight: .bold, design: .rounded)
        case .avenirNext: return .custom("AvenirNext-Bold", size: 9.5)
        case .newYork: return .system(size: 9.5, weight: .bold, design: .serif)
        }
    }

    @ViewBuilder
    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if materialEnabled || !isDarkMode {
            shape.themedGlassSurface(themeMode: appState.themeMode, isDarkMode: isDarkMode)
        } else {
            shape
                .fill(AppColors.elevatedSurfaceTint(themeMode: appState.themeMode, isDarkMode: isDarkMode))
                .overlay {
                    shape.fill(AppColors.elevatedSurfaceGlowStyle(themeMode: appState.themeMode, isDarkMode: isDarkMode))
                }
                .overlay {
                    shape.fill(AppColors.elevatedSurfaceHighlightStyle(themeMode: appState.themeMode, isDarkMode: isDarkMode))
                }
                .overlay {
                    shape.stroke(AppColors.elevatedSurfaceBorder(themeMode: appState.themeMode, isDarkMode: isDarkMode), lineWidth: 1)
                }
                .overlay {
                    shape.inset(by: 1)
                        .stroke(AppColors.elevatedSurfaceInnerBorder(themeMode: appState.themeMode, isDarkMode: isDarkMode), lineWidth: 0.8)
                }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 6)
            Text(title)
                .font(titleFont)
                .tracking(0.12)
                .foregroundStyle(isDarkMode ? Color.white.opacity(0.90) : Color.black.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.42)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 2)
            Spacer(minLength: 0)
        }
        .frame(width: 56, height: 56, alignment: .topLeading)
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(surface)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(galaxyAccentBorder(isDarkMode: isDarkMode), lineWidth: 1.05)
        )
        .shadow(color: .black.opacity(isDarkMode ? 0.14 : 0.05), radius: 3, y: 1.5)
    }
}

#if os(iOS)
private struct ExplorePinchEvent {
    let scale: CGFloat
    let location: CGPoint
    let state: UIGestureRecognizer.State
}

private struct ExplorePinchGestureBridge: UIViewRepresentable {
    let isEnabled: Bool
    let onEvent: (ExplorePinchEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent)
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.update(from: uiView, isEnabled: isEnabled)
    }

    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.refresh(from: self)
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            if newWindow == nil {
                coordinator?.detach()
            }
            super.willMove(toWindow: newWindow)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            coordinator?.refresh(from: self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onEvent: (ExplorePinchEvent) -> Void
        private var isEnabled = false
        private weak var attachedView: UIView?
        private weak var pinchRecognizer: UIPinchGestureRecognizer?

        init(onEvent: @escaping (ExplorePinchEvent) -> Void) {
            self.onEvent = onEvent
        }

        func refresh(from view: UIView) {
            update(from: view, isEnabled: isEnabled)
        }

        func update(from view: UIView, isEnabled: Bool) {
            self.isEnabled = isEnabled

            guard isEnabled, let targetView = resolveTargetView(from: view) else {
                detach()
                return
            }

            guard attachedView !== targetView else { return }

            detach()

            let recognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            targetView.addGestureRecognizer(recognizer)

            pinchRecognizer = recognizer
            attachedView = targetView
        }

        private func resolveTargetView(from view: UIView) -> UIView? {
            if let superview = view.superview,
               superview.bounds.width > 0,
               superview.bounds.height > 0 {
                return superview
            }
            return view.window
        }

        func detach() {
            if let pinchRecognizer {
                pinchRecognizer.view?.removeGestureRecognizer(pinchRecognizer)
            }
            pinchRecognizer = nil
            attachedView = nil
        }

        @objc
        private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard isEnabled else { return }
            guard let gestureView = recognizer.view else { return }
            let locationInGestureView = recognizer.location(in: gestureView)
            let locationInGlobal = gestureView.window.map {
                gestureView.convert(locationInGestureView, to: $0)
            } ?? locationInGestureView

            onEvent(
                ExplorePinchEvent(
                    scale: recognizer.scale,
                    location: locationInGlobal,
                    state: recognizer.state
                )
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
#endif

struct SearchSelectedWordCardView: View {
    let word: SimpleWord
    let themeMode: ThemeMode
    let allowsBlurrySwipe: Bool
    let dismissOnTap: Bool
    let embeddedInTabView: Bool
    let onDismiss: () -> Void
    let onSwipeForgot: (String) -> Void
    let onSwipeMastered: (String) -> Void
    let onSwipeBlurry: (String) -> Void

    init(
        word: SimpleWord,
        themeMode: ThemeMode = .system,
        allowsBlurrySwipe: Bool = true,
        dismissOnTap: Bool = false,
        embeddedInTabView: Bool = false,
        onDismiss: @escaping () -> Void,
        onSwipeForgot: @escaping (String) -> Void,
        onSwipeMastered: @escaping (String) -> Void,
        onSwipeBlurry: @escaping (String) -> Void
    ) {
        self.word = word
        self.themeMode = themeMode
        self.allowsBlurrySwipe = allowsBlurrySwipe
        self.dismissOnTap = dismissOnTap
        self.embeddedInTabView = embeddedInTabView
        self.onDismiss = onDismiss
        self.onSwipeForgot = onSwipeForgot
        self.onSwipeMastered = onSwipeMastered
        self.onSwipeBlurry = onSwipeBlurry
    }

    @Environment(\.colorScheme) private var colorScheme

    private var showHomeWallpaper: Bool {
        themeMode == .steppe
    }

    #if os(iOS)
    private static let exploreTabBarHeight: CGFloat = 49
    #endif

    var body: some View {
        GeometryReader { geo in
            let contentWidth = DiscoverCardLayout.contentWidth(forScreenWidth: geo.size.width)
            let cardHeight = DiscoverCardLayout.cardHeight(forCardWidth: contentWidth)
            #if os(iOS)
            let containerHeight: CGFloat = {
                if embeddedInTabView { return geo.size.height }
                return max(0, geo.size.height - Self.exploreTabBarHeight)
            }()
            #else
            let containerHeight = geo.size.height
            #endif
            let cardYOffset = DiscoverCardLayout.restingCardYOffset(containerHeight: containerHeight)
            ZStack {
                if dismissOnTap {
                    ThemedBackgroundView(
                        themeMode: themeMode,
                        isDarkMode: colorScheme == .dark,
                        showWallpaper: showHomeWallpaper
                    )
                        .contentShape(Rectangle())
                        .onTapGesture { onDismiss() }
                } else {
                    ThemedBackgroundView(
                        themeMode: themeMode,
                        isDarkMode: colorScheme == .dark,
                        showWallpaper: showHomeWallpaper
                    )
                }

                DiscoverCard(
                    word: word,
                    screenWidth: contentWidth,
                    cardWidth: contentWidth,
                    cardHeight: cardHeight,
                    isActiveTab: true,
                    resetTransformAfterSwipe: false,
                    allowsBlurrySwipe: allowsBlurrySwipe,
                    onSwipeUpWithoutAction: dismissOnTap ? { onDismiss() } : nil,
                    onSwipeForgot: { swipedWordId in
                        onDismiss()
                        DispatchQueue.main.async {
                            onSwipeForgot(swipedWordId)
                        }
                    },
                    onSwipeMastered: { swipedWordId in
                        onDismiss()
                        DispatchQueue.main.async {
                            onSwipeMastered(swipedWordId)
                        }
                    },
                    onSwipeBlurry: { swipedWordId in
                        onDismiss()
                        DispatchQueue.main.async {
                            onSwipeBlurry(swipedWordId)
                        }
                    }
                )
                .id(word.id)
                .frame(width: contentWidth, height: containerHeight)
                .position(x: geo.size.width / 2, y: containerHeight / 2 + cardYOffset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .interactiveDismissDisabled()
    }
}

private struct DiscoverEmptyStateView: View {
    let title: String
    let subtitle: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.50) : Color.black.opacity(0.34))
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.84) : Color.black.opacity(0.76))
            Text(subtitle)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.56) : Color.black.opacity(0.48))
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct DeckCompletionCelebrationView: View {
    @EnvironmentObject private var appState: AppState
    @State private var burstProgress: CGFloat = 0
    @State private var emojiPulse = false
    @State private var textLift = false
    @State private var didAnimate = false
    private let confettiColors: [Color] = [
        Color(red: 0.15, green: 0.84, blue: 0.48),
        Color(red: 0.14, green: 0.60, blue: 1.00),
        Color(red: 1.00, green: 0.74, blue: 0.22),
        Color(red: 1.00, green: 0.45, blue: 0.34)
    ]

    private func celebrationFont(_ textStyle: Font.TextStyle, weight: Font.Weight) -> Font {
        switch appState.cardFontStyle {
        case .sfPro:
            return .system(textStyle, design: .default, weight: weight)
        case .sfRounded:
            return .system(textStyle, design: .rounded, weight: weight)
        case .newYork:
            return .system(textStyle, design: .serif, weight: weight)
        case .avenirNext:
            let base: CGFloat
            switch textStyle {
            case .title: base = 28
            case .subheadline: base = 15
            default: base = 17
            }
            return Font.custom(celebrationAvenirName(for: weight), size: base, relativeTo: textStyle)
        }
    }

    private func celebrationAvenirName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold: return "AvenirNext-Bold"
        case .semibold: return "AvenirNext-DemiBold"
        case .medium: return "AvenirNext-Medium"
        default: return "AvenirNext-Regular"
        }
    }

    var body: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { index in
                let angle = (Double(index) / 18.0) * (Double.pi * 2)
                let baseRadius: CGFloat = 28
                let burstRadius = baseRadius + 136 * burstProgress
                let x = CGFloat(cos(angle)) * burstRadius
                let y = CGFloat(sin(angle)) * burstRadius * 0.76

                Group {
                    if index.isMultiple(of: 3) {
                        Capsule()
                            .fill(confettiColors[index % confettiColors.count])
                            .frame(width: 8, height: 22)
                    } else if index.isMultiple(of: 2) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(confettiColors[index % confettiColors.count])
                            .frame(width: 10, height: 10)
                    } else {
                        Circle()
                            .fill(confettiColors[index % confettiColors.count])
                            .frame(width: 9, height: 9)
                    }
                }
                .opacity(Double(max(0.0, 0.96 - burstProgress)))
                .scaleEffect(max(0.42, 1.04 - burstProgress * 0.68))
                .rotationEffect(.degrees(Double(index * 11)) + .degrees(Double(burstProgress) * 18))
                .offset(x: x, y: y)
            }

            VStack(spacing: 14) {
                HStack(spacing: -12) {
                    PartyPopperSymbolView(size: 58)
                        .rotationEffect(.degrees(emojiPulse ? -10 : -20))
                        .offset(y: emojiPulse ? 0 : 10)

                    PartyPopperSymbolView(size: 84)
                        .rotationEffect(.degrees(emojiPulse ? 0 : -6))
                        .offset(y: emojiPulse ? -6 : 8)

                    PartyPopperSymbolView(size: 58)
                        .rotationEffect(.degrees(emojiPulse ? 10 : 20))
                        .offset(y: emojiPulse ? 0 : 10)
                }
                .scaleEffect(emojiPulse ? 1.0 : 0.78)

                Text(appState.localized("Amazing, today's goal complete!", "太棒了，今日目标已完成！", "शानदार, आज का लक्ष्य पूरा!"))
                    .font(celebrationFont(.title, weight: .bold))
                    .foregroundStyle(.secondary)
                    .offset(y: textLift ? -2 : 2)

                Text(appState.localized("More cards coming up…", "更多卡片即将出现…", "और कार्ड आ रहे हैं…"))
                    .font(celebrationFont(.subheadline, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .offset(y: textLift ? -1 : 1)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 30)
        .onAppear {
            guard !didAnimate else { return }
            didAnimate = true
            burstProgress = 0
            emojiPulse = false
            textLift = false
            withAnimation(.easeOut(duration: 1.1)) {
                burstProgress = 1
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.62).delay(0.06)) {
                emojiPulse = true
            }
            withAnimation(.easeOut(duration: 0.55).delay(0.12)) {
                textLift = true
            }
        }
    }
}

private struct PartyPopperSymbolView: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "party.popper.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                Color(red: 1.00, green: 0.54, blue: 0.20),
                Color(red: 1.00, green: 0.80, blue: 0.22),
                Color(red: 0.18, green: 0.78, blue: 0.44)
            )
            .font(.system(size: size * 0.82, weight: .regular))
            .frame(width: size, height: size)
    }
}

private struct DiscoverCard: View {
    let word: SimpleWord
    let screenWidth: CGFloat
    let cardWidth: CGFloat?
    let cardHeight: CGFloat?
    let isActiveTab: Bool
    let detailProgress: Double
    let glowStrength: Double
    let contentOpacity: Double
    let interactionsEnabled: Bool
    let resetTransformAfterSwipe: Bool
    let allowsBlurrySwipe: Bool
    let onSwipeDownAction: (() -> Void)?
    let onSwipeUpWithoutAction: (() -> Void)?
    let onSwipeForgot: (String) -> Void
    let onSwipeMastered: (String) -> Void
    let onSwipeBlurry: (String) -> Void
    let onDragChanged: ((CGSize) -> Void)?

    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOffset: CGSize = .zero
    @State private var dragRotation: Angle = .zero
    @State private var isSwipeCompleting = false
    @State private var pendingSpeechTask: Task<Void, Never>?
    @State private var displayedWord: SimpleWord
    @State private var allSenses: [SimpleWord] = []
    @State private var currentSensePosition: Int = 0

    init(
        word: SimpleWord,
        screenWidth: CGFloat,
        cardWidth: CGFloat? = nil,
        cardHeight: CGFloat? = nil,
        isActiveTab: Bool,
        detailProgress: Double = 1,
        glowStrength: Double = 1,
        contentOpacity: Double = 1,
        interactionsEnabled: Bool = true,
        resetTransformAfterSwipe: Bool = true,
        allowsBlurrySwipe: Bool = true,
        onSwipeDownAction: (() -> Void)? = nil,
        onSwipeUpWithoutAction: (() -> Void)? = nil,
        onSwipeForgot: @escaping (String) -> Void,
        onSwipeMastered: @escaping (String) -> Void,
        onSwipeBlurry: @escaping (String) -> Void,
        onDragChanged: ((CGSize) -> Void)? = nil
    ) {
        self.word = word
        self.screenWidth = screenWidth
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.isActiveTab = isActiveTab
        self.detailProgress = detailProgress
        self.glowStrength = glowStrength
        self.contentOpacity = contentOpacity
        self.interactionsEnabled = interactionsEnabled
        self.resetTransformAfterSwipe = resetTransformAfterSwipe
        self.allowsBlurrySwipe = allowsBlurrySwipe
        self.onSwipeDownAction = onSwipeDownAction
        self.onSwipeUpWithoutAction = onSwipeUpWithoutAction
        self.onSwipeForgot = onSwipeForgot
        self.onSwipeMastered = onSwipeMastered
        self.onSwipeBlurry = onSwipeBlurry
        self.onDragChanged = onDragChanged
        _displayedWord = State(initialValue: word)
    }

    private let swipeThreshold: CGFloat = 100
    private enum SwipeHintDirection {
        case forgot
        case mastered
        case blurry
        case noAction
    }
    private var activeHintDirection: SwipeHintDirection? {
        let absX = abs(dragOffset.width)
        let absY = abs(dragOffset.height)
        guard max(absX, absY) > 0 else { return nil }
        if absY >= absX {
            if dragOffset.height > 0, allowsBlurrySwipe {
                return .blurry
            }
            if dragOffset.height < 0, onSwipeUpWithoutAction != nil {
                return .noAction
            }
        } else {
            if dragOffset.width < 0 {
                return .forgot
            }
            if dragOffset.width > 0 {
                return .mastered
            }
        }
        return nil
    }
    private var forgotHintOpacity: Double {
        guard activeHintDirection == .forgot, dragOffset.width < 0 else { return 0 }
        return min(0.35 + Double(abs(dragOffset.width) / 45), 1)
    }
    private var masteredHintOpacity: Double {
        guard activeHintDirection == .mastered, dragOffset.width > 0 else { return 0 }
        return min(0.35 + Double(abs(dragOffset.width) / 45), 1)
    }
    private var blurryHintOpacity: Double {
        guard activeHintDirection == .blurry, dragOffset.height > 0 else { return 0 }
        return min(0.15 + Double(abs(dragOffset.height) / 90), 1)
    }
    private var noActionHintOpacity: Double {
        guard activeHintDirection == .noAction, dragOffset.height < 0, onSwipeUpWithoutAction != nil else { return 0 }
        return min(0.20 + Double(abs(dragOffset.height) / 90), 1)
    }
    private var resolvedCardWidth: CGFloat {
        max(cardWidth ?? screenWidth, 0)
    }
    private var resolvedCardHeight: CGFloat {
        max(cardHeight ?? DiscoverCardLayout.cardHeight(forCardWidth: resolvedCardWidth), 0)
    }
    private var isDarkMode: Bool { colorScheme == .dark }
    private var secondaryTextColor: Color {
        isDarkMode ? AppColors.nocturneTextSecondary : Color.black.opacity(0.42)
    }

    private var swipeHintTextColor: Color {
        Color.primary.opacity(isDarkMode ? 0.38 : 0.42)
    }

    private func swipeHintFont() -> Font {
        let scaled = UIFontMetrics(forTextStyle: .title3).scaledValue(for: 20)
        switch appState.cardFontStyle {
        case .sfPro:
            return .system(size: scaled, weight: .semibold, design: .default)
        case .sfRounded:
            return .system(size: scaled, weight: .semibold, design: .rounded)
        case .avenirNext:
            return .custom("AvenirNext-DemiBold", size: scaled)
        case .newYork:
            return .system(size: scaled, weight: .semibold, design: .serif)
        }
    }

    private var bottomMetaReveal: Double {
        galaxySmoothStep((detailProgress - 0.10) / 0.72)
    }

    private func speakWord() {
        let trimmedWord = displayedWord.displayWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }
        
        OpenAITTSService.stopPlayback()
        OpenAITTSService.speakText(trimmedWord, language: "fr-FR", contentType: .word)
    }

    private func speakExampleSentence() {
        let trimmedExample = displayedWord.exampleFr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExample.isEmpty else { return }

        OpenAITTSService.stopPlayback()
        OpenAITTSService.speakText(trimmedExample, language: "fr-FR", contentType: .sentence)
    }

    private func cancelScheduledSpeech() {
        pendingSpeechTask?.cancel()
        pendingSpeechTask = nil
    }

    private func stopSpeechPlayback() {
        cancelScheduledSpeech()
        OpenAITTSService.stopPlayback()
    }

    private func scheduleAutoPlay(delay: TimeInterval = 0.32) {
        cancelScheduledSpeech()
        let delayInNanoseconds = UInt64(delay * 1_000_000_000)
        pendingSpeechTask = Task { @MainActor in
            if delayInNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayInNanoseconds)
            }
            guard !Task.isCancelled else { return }
            guard isActiveTab, appState.autoPlay else { return }
            speakWord()
        }
    }

    private var hasMultipleSenses: Bool {
        allSenses.count > 1
    }

    private func refreshSenses(using source: SimpleWord) {
        let senses = appState.getAllSenses(source)
        if senses.isEmpty {
            allSenses = [source]
            displayedWord = source
            currentSensePosition = 0
            return
        }

        allSenses = senses
        if let selected = senses.firstIndex(where: { $0.id == displayedWord.id }) {
            currentSensePosition = selected
            displayedWord = senses[selected]
            return
        }
        if let initial = senses.firstIndex(where: { $0.id == source.id }) {
            currentSensePosition = initial
            displayedWord = senses[initial]
            return
        }
        currentSensePosition = 0
        displayedWord = senses[0]
    }

    private func showNextSense() {
        guard hasMultipleSenses else { return }
        let next = (currentSensePosition + 1) % allSenses.count
        withAnimation(.easeInOut(duration: 0.18)) {
            currentSensePosition = next
            displayedWord = allSenses[next]
        }
    }

    private func completeSwipe(
        to offset: CGSize,
        after delay: TimeInterval = 0.2,
        action: @escaping () -> Void
    ) {
        guard !isSwipeCompleting else { return }
        isSwipeCompleting = true

        withAnimation(.easeOut(duration: delay)) {
            dragOffset = offset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            action()
            if resetTransformAfterSwipe {
                dragOffset = .zero
                dragRotation = .zero
            }
            isSwipeCompleting = false
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                if noActionHintOpacity > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(secondaryTextColor)
                        Text(appState.localized("No action", "无操作", "कोई कार्रवाई नहीं"))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                    }
                    .opacity(noActionHintOpacity)
                    .frame(maxWidth: resolvedCardWidth)
                }

                CardBody(
                    word: displayedWord,
                    cardWidth: cardWidth ?? 0,
                    cardHeight: cardHeight ?? 0,
                    detailProgress: detailProgress,
                    contentOpacity: contentOpacity,
                    onTitleTap: { [self] in cancelScheduledSpeech(); speakWord() },
                    onDetailTap: { [self] in cancelScheduledSpeech(); speakExampleSentence() }
                )
                    .overlay(alignment: .bottomTrailing) {
                        bottomMetaBar
                            .padding(.trailing, 12)
                            .padding(.bottom, 12)
                            .opacity(bottomMetaReveal)
                    }
                    .modifier(CardGlowModifier(strength: glowStrength, isDarkMode: isDarkMode))

                ZStack {
                    if forgotHintOpacity > 0 {
                        Text(appState.localized("Forgot", "忘记", "भूल गया"))
                            .font(swipeHintFont())
                            .foregroundStyle(swipeHintTextColor)
                            .opacity(forgotHintOpacity)
                            .multilineTextAlignment(.center)
                    }
                    if masteredHintOpacity > 0 {
                        Text(appState.localized("Mastered", "掌握", "सीख लिया"))
                            .font(swipeHintFont())
                            .foregroundStyle(swipeHintTextColor)
                            .opacity(masteredHintOpacity)
                            .multilineTextAlignment(.center)
                    }
                    if allowsBlurrySwipe && blurryHintOpacity > 0 {
                        Text(appState.localized("Blurry", "模糊", "धुंधला"))
                            .font(swipeHintFont())
                            .foregroundStyle(swipeHintTextColor)
                            .opacity(blurryHintOpacity)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: resolvedCardWidth)
            }
            .offset(dragOffset)
            .rotationEffect(dragRotation)
            .allowsHitTesting(interactionsEnabled)
            .gesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { v in
                        guard interactionsEnabled, !isSwipeCompleting else { return }
                        dragOffset = v.translation
                        dragRotation = .degrees(Double(v.translation.width / screenWidth * 12))
                        onDragChanged?(v.translation)
                    }
                    .onEnded { v in
                        guard interactionsEnabled, !isSwipeCompleting else { return }
                        let dx = v.translation.width
                        let dy = v.translation.height
                        if dx < -swipeThreshold {
                            let swipedWordId = displayedWord.id
                            FeedbackService.swipeForgot()
                            onDragChanged?(CGSize(width: 500, height: 0))
                            completeSwipe(to: CGSize(width: -screenWidth, height: 0)) {
                                onSwipeForgot(swipedWordId)
                            }
                        } else if dx > swipeThreshold {
                            let swipedWordId = displayedWord.id
                            FeedbackService.swipeMastered()
                            onDragChanged?(CGSize(width: 500, height: 0))
                            completeSwipe(to: CGSize(width: screenWidth, height: 0)) {
                                onSwipeMastered(swipedWordId)
                            }
                        } else if dy > swipeThreshold, let onSwipeDownAction {
                            FeedbackService.swipeBlurry()
                            onDragChanged?(CGSize(width: 500, height: 0))
                            completeSwipe(to: CGSize(width: 0, height: 400), action: onSwipeDownAction)
                        } else if dy > swipeThreshold && allowsBlurrySwipe {
                            let swipedWordId = displayedWord.id
                            FeedbackService.swipeBlurry()
                            onDragChanged?(CGSize(width: 500, height: 0))
                            completeSwipe(to: CGSize(width: 0, height: 400)) {
                                onSwipeBlurry(swipedWordId)
                            }
                        } else if dy < -swipeThreshold, let onSwipeUpWithoutAction {
                            FeedbackService.swipeNoAction()
                            onSwipeUpWithoutAction()
                            onDragChanged?(.zero)
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                dragOffset = .zero
                                dragRotation = .zero
                            }
                            onDragChanged?(.zero)
                        }
                    }
            )
            .onChange(of: appState.autoPlay) { _, enabled in
                if !enabled {
                    stopSpeechPlayback()
                }
            }
            .onChange(of: isActiveTab) { _, active in
                if !active {
                    stopSpeechPlayback()
                }
            }
            .onChange(of: word.id) { _, _ in
                refreshSenses(using: word)
                if interactionsEnabled && isActiveTab && appState.autoPlay {
                    scheduleAutoPlay()
                }
            }
            .onDisappear {
                stopSpeechPlayback()
            }
            .onAppear {
                refreshSenses(using: word)
                if interactionsEnabled {
                    FeedbackService.prepareInteractive()
                }
                if interactionsEnabled && isActiveTab && appState.autoPlay {
                    scheduleAutoPlay()
                }
            }
        }
    }

    @ViewBuilder
    private var bottomMetaBar: some View {
        if hasMultipleSenses {
            Button(action: showNextSense) {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(displayedWord.senseIndex)/\(allSenses.count)")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(secondaryTextColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ConditionalBlur: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        if radius > 0 {
            content.blur(radius: radius)
        } else {
            content
        }
    }
}

private struct OptionalTapModifier: ViewModifier {
    let action: (() -> Void)?
    func body(content: Content) -> some View {
        if let action {
            content.contentShape(Rectangle()).onTapGesture { action() }
        } else {
            content
        }
    }
}

private struct CardGlowModifier: ViewModifier {
    let strength: Double
    let isDarkMode: Bool

    private var glowColor: Color {
        isDarkMode
            ? Color(red: 0.31, green: 1.00, blue: 0.66)
            : Color(red: 0.51, green: 0.86, blue: 0.75)
    }

    func body(content: Content) -> some View {
        if strength > 0.001 {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(glowColor.opacity((isDarkMode ? 0.64 : 0.42) * strength), lineWidth: isDarkMode ? 1.8 : 1.6)
                        .blur(radius: isDarkMode ? 1.8 : 2)
                )
                .shadow(color: glowColor.opacity((isDarkMode ? 0.30 : 0.22) * strength), radius: isDarkMode ? 8 : 12, x: 0, y: 0)
                .shadow(color: glowColor.opacity((isDarkMode ? 0.18 : 0.12) * strength), radius: isDarkMode ? 18 : 24, x: 0, y: 0)
                .shadow(color: glowColor.opacity((isDarkMode ? 0.11 : 0.07) * strength), radius: isDarkMode ? 34 : 38, x: 0, y: 0)
        } else {
            content
        }
    }
}

private struct CardBody: View {
    let word: SimpleWord
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let detailProgress: Double
    var contentOpacity: Double = 1.0
    var onTitleTap: (() -> Void)? = nil
    var onDetailTap: (() -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    private enum CardFontWeight {
        case regular, medium, semibold, bold
    }

    private enum NounCornerTone {
        case green, red, lavender
    }

    private var isDarkMode: Bool { colorScheme == .dark }

    private var levelTextColor: Color { AppColors.tertiaryText(isDarkMode: isDarkMode) }
    private var headlineTextColor: Color { AppColors.primaryText(isDarkMode: isDarkMode) }
    private var secondaryTextColor: Color {
        isDarkMode ? AppColors.nocturneTextSecondary : Color.black.opacity(0.42)
    }
    private var bodyTextColor: Color {
        isDarkMode ? Color.white.opacity(0.80) : Color.black.opacity(0.78)
    }
    private var dividerColor: Color {
        isDarkMode ? AppColors.nocturneBorderSoft : Color.black.opacity(0.14)
    }
    private var exampleTextColor: Color {
        isDarkMode ? AppColors.nocturneTextSecondary : Color.black.opacity(0.72)
    }
    private var exampleTranslationColor: Color {
        isDarkMode ? AppColors.nocturneTextTertiary : Color.black.opacity(0.48)
    }

    private var titleBaseFontSize: CGFloat {
        let count = word.displayWord.count
        if count >= 24 { return 42 }
        if count >= 20 { return 46 }
        if count >= 16 { return 50 }
        return 56
    }

    private func cardFont(size: CGFloat, weight: CardFontWeight = .regular) -> Font {
        switch appState.cardFontStyle {
        case .sfPro:
            return .system(size: size, weight: systemFontWeight(for: weight), design: .default)
        case .sfRounded:
            return .system(size: size, weight: systemFontWeight(for: weight), design: .rounded)
        case .avenirNext:
            return .custom(avenirNextFontName(for: weight), size: size)
        case .newYork:
            return .system(size: size, weight: systemFontWeight(for: weight), design: .serif)
        }
    }

    private func systemFontWeight(for weight: CardFontWeight) -> Font.Weight {
        switch weight {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    private func avenirNextFontName(for weight: CardFontWeight) -> String {
        switch weight {
        case .regular: return "AvenirNext-Regular"
        case .medium: return "AvenirNext-Medium"
        case .semibold: return "AvenirNext-DemiBold"
        case .bold: return "AvenirNext-Bold"
        }
    }

    private var nounFlags: Set<String> { Set(word.nounUIFlags) }
    private var nounEntityType: String { word.nounUIEntityType }

    private var isNounCard: Bool {
        let normalizedTag = word.tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedTag == "n" || normalizedTag.hasPrefix("n.") else { return false }
        return nounEntityType.isEmpty || nounEntityType.contains("name") || nounEntityType.contains("entity")
    }

    private var nounCornerTone: NounCornerTone? {
        guard isNounCard else { return nil }
        if nounFlags.contains("common_gender") || nounFlags.contains("proper_noun_like") {
            return .lavender
        }
        switch word.nounUICorner {
        case "green": return .green
        case "red": return .red
        case "dual", "neutral", "lavender": return .lavender
        case "not_applicable": return nil
        default: return nil
        }
    }

    private var nounCornerColor: Color {
        guard let tone = nounCornerTone else { return .clear }
        switch tone {
        case .green:
            return isDarkMode ? Color(red: 0.45, green: 0.81, blue: 0.66) : Color(red: 0.43, green: 0.77, blue: 0.62)
        case .red:
            return isDarkMode ? Color(red: 0.83, green: 0.51, blue: 0.54) : Color(red: 0.86, green: 0.49, blue: 0.51)
        case .lavender:
            return isDarkMode ? Color(red: 0.72, green: 0.66, blue: 0.88) : Color(red: 0.71, green: 0.62, blue: 0.88)
        }
    }

    private var primaryReveal: Double {
        detailProgress
    }

    private var secondaryReveal: Double {
        galaxySmoothStep((detailProgress - 0.10) / 0.72)
    }

    @ViewBuilder
    private var nounCornerBadge: some View {
        if nounCornerTone != nil {
            NounCornerAccentShape()
                .stroke(
                    nounCornerColor.opacity(isDarkMode ? 0.96 : 0.92),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 84, height: 72)
                .padding(.top, 8)
                .padding(.trailing, 8)
                .allowsHitTesting(false)
        }
    }

    private func layerOpacity(delay: Double) -> Double {
        guard contentOpacity < 1.0 else { return 1.0 }
        return min(1.0, max(0.0, (contentOpacity - delay) / max(0.01, 1.0 - delay)))
    }

    var body: some View {
        cardContent
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(width: cardWidth, alignment: .top)
            .overlay(alignment: .topTrailing) {
                nounCornerBadge
                    .opacity(primaryReveal * contentOpacity)
            }
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .themedGlassSurface(themeMode: appState.themeMode, isDarkMode: isDarkMode, elevated: true)
            )
            .shadow(color: Color.black.opacity(isDarkMode ? 0.18 : 0.05), radius: isDarkMode ? 16 : 10, x: 0, y: isDarkMode ? 8 : 4)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(word.level.uppercased())
                    if !word.auxiliary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(word.auxiliary)
                    }
                }
                .font(cardFont(size: 10 * (2.0 / 3.0), weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(levelTextColor)
                .opacity(primaryReveal * 0.78 * layerOpacity(delay: 0.0))
                .offset(y: -8)
                Text(word.displayWord)
                    .font(cardFont(size: titleBaseFontSize, weight: .semibold))
                    .tracking(0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.42)
                    .allowsTightening(true)
                    .foregroundStyle(headlineTextColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 20)
                    .opacity(layerOpacity(delay: 0.18))
            }
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(OptionalTapModifier(action: onTitleTap))

            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
                .padding(.bottom, 20)
                .opacity((0.18 + primaryReveal * 0.82) * layerOpacity(delay: 0.36))

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Text(posLabel(word.tag))
                        .font(cardFont(size: 16, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                        .padding(.top, 1)

                    Text(appState.translationText(for: word))
                        .font(cardFont(size: 16))
                        .lineSpacing(5)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(bodyTextColor)
                }
                .multilineTextAlignment(.leading)
                .opacity(primaryReveal * layerOpacity(delay: 0.54))

                let translatedExample = appState.translatedExampleText(for: word)
                if !word.exampleFr.isEmpty || !translatedExample.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if !word.exampleFr.isEmpty {
                            Text(word.exampleFr)
                                .foregroundStyle(exampleTextColor)
                                .font(cardFont(size: 16))
                                .multilineTextAlignment(.leading)
                                .lineSpacing(3)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !translatedExample.isEmpty {
                            Text(translatedExample)
                                .font(cardFont(size: 15))
                                .multilineTextAlignment(.leading)
                                .lineSpacing(2)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(exampleTranslationColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 18)
                    .opacity(secondaryReveal * layerOpacity(delay: 0.70))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(OptionalTapModifier(action: onDetailTap))
        }
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
    }
}

private struct TransitionDiscoverCard: View {
    let word: SimpleWord
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let contentRevealProgress: Double

    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    private enum CardFontWeight {
        case regular
        case medium
        case semibold
        case bold
    }

    private enum NounCornerTone {
        case green
        case red
        case lavender
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var cardSurfaceColor: Color {
        AppColors.elevatedSurfaceFill(themeMode: appState.themeMode, isDarkMode: isDarkMode)
    }

    private var cardBorderColor: Color {
        AppColors.elevatedSurfaceBorder(themeMode: appState.themeMode, isDarkMode: isDarkMode)
    }

    private var cardGlowColor: Color {
        isDarkMode
            ? Color(red: 0.31, green: 1.00, blue: 0.66)
            : Color(red: 0.51, green: 0.86, blue: 0.75)
    }

    private var accentBorder: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.28, green: 0.95, blue: 0.56).opacity(isDarkMode ? 0.82 : 0.62),
                Color(red: 0.16, green: 0.78, blue: 0.46).opacity(isDarkMode ? 0.72 : 0.52)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var levelTextColor: Color {
        AppColors.tertiaryText(isDarkMode: isDarkMode)
    }

    private var headlineTextColor: Color {
        AppColors.primaryText(isDarkMode: isDarkMode)
    }

    private var secondaryTextColor: Color {
        isDarkMode ? AppColors.nocturneTextSecondary : Color.black.opacity(0.42)
    }

    private var bodyTextColor: Color {
        isDarkMode ? Color.white.opacity(0.80) : Color.black.opacity(0.78)
    }

    private var dividerColor: Color {
        isDarkMode ? AppColors.nocturneBorderSoft : Color.black.opacity(0.14)
    }

    private var exampleTextColor: Color {
        isDarkMode ? AppColors.nocturneTextSecondary : Color.black.opacity(0.72)
    }

    private var exampleTranslationColor: Color {
        isDarkMode ? AppColors.nocturneTextTertiary : Color.black.opacity(0.48)
    }

    private var titleBaseFontSize: CGFloat {
        let count = word.displayWord.count
        if count >= 24 { return 42 }
        if count >= 20 { return 46 }
        if count >= 16 { return 50 }
        return 56
    }

    private func cardFont(size: CGFloat, weight: CardFontWeight = .regular) -> Font {
        switch appState.cardFontStyle {
        case .sfPro:
            return .system(size: size, weight: systemFontWeight(for: weight), design: .default)
        case .sfRounded:
            return .system(size: size, weight: systemFontWeight(for: weight), design: .rounded)
        case .avenirNext:
            return .custom(avenirNextFontName(for: weight), size: size)
        case .newYork:
            return .system(size: size, weight: systemFontWeight(for: weight), design: .serif)
        }
    }

    private func systemFontWeight(for weight: CardFontWeight) -> Font.Weight {
        switch weight {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    private func avenirNextFontName(for weight: CardFontWeight) -> String {
        switch weight {
        case .regular: return "AvenirNext-Regular"
        case .medium: return "AvenirNext-Medium"
        case .semibold: return "AvenirNext-DemiBold"
        case .bold: return "AvenirNext-Bold"
        }
    }

    private var detailProgress: Double {
        let t = min(1.0, max(0.0, (contentRevealProgress - 0.38) / 0.62))
        return t * t * (3 - 2 * t)
    }

    private var nounFlags: Set<String> {
        Set(word.nounUIFlags)
    }

    private var nounEntityType: String {
        word.nounUIEntityType
    }

    private var isNounCard: Bool {
        let normalizedTag = word.tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedTag == "n" || normalizedTag.hasPrefix("n.") else { return false }
        return nounEntityType.isEmpty || nounEntityType.contains("name") || nounEntityType.contains("entity")
    }

    private var nounCornerTone: NounCornerTone? {
        guard isNounCard else { return nil }
        if nounFlags.contains("common_gender") || nounFlags.contains("proper_noun_like") {
            return .lavender
        }
        switch word.nounUICorner {
        case "green":
            return .green
        case "red":
            return .red
        case "dual", "neutral", "lavender":
            return .lavender
        case "not_applicable":
            return nil
        default:
            return nil
        }
    }

    private var nounCornerColor: Color {
        guard let tone = nounCornerTone else { return .clear }
        switch tone {
        case .green:
            return isDarkMode ? Color(red: 0.45, green: 0.81, blue: 0.66) : Color(red: 0.43, green: 0.77, blue: 0.62)
        case .red:
            return isDarkMode ? Color(red: 0.83, green: 0.51, blue: 0.54) : Color(red: 0.86, green: 0.49, blue: 0.51)
        case .lavender:
            return isDarkMode ? Color(red: 0.72, green: 0.66, blue: 0.88) : Color(red: 0.71, green: 0.62, blue: 0.88)
        }
    }

    @ViewBuilder
    private var nounCornerBadge: some View {
        if nounCornerTone != nil {
            NounCornerAccentShape()
                .stroke(
                    nounCornerColor.opacity(isDarkMode ? 0.96 : 0.92),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 84, height: 72)
                .padding(.top, 8)
                .padding(.trailing, 8)
                .allowsHitTesting(false)
        }
    }

    var body: some View {
        cardContent
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
            .frame(width: cardWidth, alignment: .top)
            .overlay(alignment: .topTrailing) {
                nounCornerBadge
                    .opacity(detailProgress)
            }
            .background(cardSurfaceColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(cardBorderColor, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(accentBorder, lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(isDarkMode ? 0.14 : 0.05), radius: 10, x: 0, y: 4)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(word.level.uppercased())
                    if !word.auxiliary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(word.auxiliary)
                    }
                }
                .font(cardFont(size: 11 * (2.0 / 3.0), weight: .semibold))
                .foregroundStyle(levelTextColor)
                .opacity(detailProgress)
                .offset(y: -8)
                Text(word.displayWord)
                    .font(cardFont(size: titleBaseFontSize, weight: .semibold))
                    .tracking(0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.42)
                    .allowsTightening(true)
                    .foregroundStyle(headlineTextColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 22)
            }
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
                .padding(.bottom, 20)
                .opacity(0.18 + detailProgress * 0.82)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Text(posLabel(word.tag))
                        .font(cardFont(size: 16, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                        .padding(.top, 1)

                    Text(appState.translationText(for: word))
                        .font(cardFont(size: 16))
                        .lineSpacing(5)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(bodyTextColor)
                }
                .multilineTextAlignment(.leading)

                let translatedExample = appState.translatedExampleText(for: word)
                if !word.exampleFr.isEmpty || !translatedExample.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if !word.exampleFr.isEmpty {
                            Text(word.exampleFr)
                                .foregroundStyle(exampleTextColor)
                                .font(cardFont(size: 16))
                                .multilineTextAlignment(.leading)
                                .lineSpacing(3)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !translatedExample.isEmpty {
                            Text(translatedExample)
                                .font(cardFont(size: 15))
                                .multilineTextAlignment(.leading)
                                .lineSpacing(2)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(exampleTranslationColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(detailProgress)
        }
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
    }
}

private struct NounCornerAccentShape: Shape {
    func path(in rect: CGRect) -> Path {
        let leg: CGFloat = min(rect.width, rect.height) * 0.30
        let inset: CGFloat = 8
        let radius: CGFloat = 9
        let maxX = rect.maxX - inset
        let minY = rect.minY + inset

        var path = Path()
        path.move(to: CGPoint(x: maxX - leg, y: minY))
        path.addLine(to: CGPoint(x: maxX - radius, y: minY))
        path.addArc(
            center: CGPoint(x: maxX - radius, y: minY + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: maxX, y: minY + leg))
        return path
    }
}

#Preview("Noun Corner Badge") {
    DiscoverCard(
        word: SimpleWord(
            id: "preview_noun_corner",
            word: "paléontologue",
            tag: "N",
            level: "B2",
            translationZh: "古生物学家",
            translationEn: "paleontologist",
            exampleFr: "Le paleontologue etudie les fossiles.",
            exampleZh: "古生物学家研究化石。",
            displayWord: "un paléontologue",
            nounUICorner: "red",
            nounUIFlags: [],
            nounUIEntityType: "named_entity"
        ),
        screenWidth: 390,
        cardHeight: 342,
        isActiveTab: true,
        onSwipeForgot: { _ in },
        onSwipeMastered: { _ in },
        onSwipeBlurry: { _ in }
    )
    .padding(.horizontal, 20)
    .frame(width: 430, height: 420)
    .environmentObject(AppState())
}

private let progressRevealCoordinateSpace = "progress-screen-reveal"

private struct ProgressScreen: View {
    private enum ProgressBucket: CaseIterable, Hashable {
        case forgot
        case blurry
        case mastered

        @MainActor
        func title(using appState: AppState) -> String {
            switch self {
            case .forgot: return appState.localized("Forgot", "忘记", "भूल गया")
            case .blurry: return appState.localized("Blurry", "模糊", "धुंधला")
            case .mastered: return appState.localized("Mastered", "掌握", "सीख लिया")
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var srsManager: SRSManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedBucket: ProgressBucket = .forgot
    @State private var selectedWordForCard: SimpleWord?
    @State private var isWordCardVisible = false
    @State private var wordCardRevealOrigin: CGPoint = .zero
    private var displayedWords: [SimpleWord] { Array(filteredWords.prefix(20)) }
    private var isDarkMode: Bool { colorScheme == .dark }
    private var bucketLabels: [String] {
        ProgressBucket.allCases.map { $0.title(using: appState) }
    }
    private var selectedBucketIndex: Int {
        ProgressBucket.allCases.firstIndex(of: selectedBucket) ?? 0
    }

    private var filteredWords: [SimpleWord] {
        switch selectedBucket {
        case .forgot: return srsManager.getForgotWords()
        case .blurry: return srsManager.getBlurryWords()
        case .mastered: return srsManager.getMasteredWords()
        }
    }

    private func presentWordCard(_ word: SimpleWord, at origin: CGPoint) {
        wordCardRevealOrigin = origin
        selectedWordForCard = word
        isWordCardVisible = false
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.34)) {
                isWordCardVisible = true
            }
        }
    }

    private func dismissWordCard() {
        guard selectedWordForCard != nil else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            isWordCardVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            if !isWordCardVisible {
                selectedWordForCard = nil
            }
        }
    }

    private func clampedRevealOrigin(in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(wordCardRevealOrigin.x, 0), size.width),
            y: min(max(wordCardRevealOrigin.y, 0), size.height)
        )
    }

    private func revealRadius(in size: CGSize, from origin: CGPoint) -> CGFloat {
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height)
        ]
        return (corners.map { hypot($0.x - origin.x, $0.y - origin.y) }.max() ?? 0) + 48
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 18) {
                    Spacer().frame(height: 10)

                    CheckInHeatmapView()
                        .frame(height: 186)
                        .padding(.horizontal, 20)

                    PillSelector(labels: bucketLabels, selectedIndex: selectedBucketIndex, style: .glossy) { idx in
                        guard idx < ProgressBucket.allCases.count else { return }
                        selectedBucket = ProgressBucket.allCases[idx]
                    }
                    .padding(.horizontal, 20)

                    if displayedWords.isEmpty {
                        Text(appState.localized("No words yet", "暂无单词", "अभी कोई शब्द नहीं"))
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(isDarkMode ? Color.white.opacity(0.46) : Color.black.opacity(0.40))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 24)
                        Spacer(minLength: 180)
                    } else {
                        List {
                            ForEach(displayedWords) { word in
                                ProgressWordRow(
                                    word: word,
                                    onDelete: {
                                        withAnimation(.easeInOut(duration: 0.20)) {
                                            srsManager.resetWordToNew(word.id)
                                        }
                                    },
                                    onTap: { tapLocation in
                                        presentWordCard(word, at: tapLocation)
                                    }
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 36, bottom: 4, trailing: 20))
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if let word = selectedWordForCard {
                    let origin = clampedRevealOrigin(in: geo.size)
                    let radius = revealRadius(in: geo.size, from: origin)
                    SearchSelectedWordCardView(
                        word: word,
                        themeMode: appState.themeMode,
                        allowsBlurrySwipe: true,
                        dismissOnTap: true,
                        embeddedInTabView: true,
                        onDismiss: { dismissWordCard() },
                        onSwipeForgot: {
                            srsManager.markWordForgot(
                                $0,
                                persistDuringInfinitePractice: true,
                                affectsDailyProgress: false
                            )
                        },
                        onSwipeMastered: {
                            srsManager.markWordMastered(
                                $0,
                                persistDuringInfinitePractice: true,
                                affectsDailyProgress: false
                            )
                        },
                        onSwipeBlurry: {
                            srsManager.markWordBlurry(
                                $0,
                                persistDuringInfinitePractice: true,
                                affectsDailyProgress: false
                            )
                        }
                    )
                    .id(word.id)
                    .mask(
                        Circle()
                            .frame(
                                width: isWordCardVisible ? radius * 2 : 2,
                                height: isWordCardVisible ? radius * 2 : 2
                            )
                            .position(origin)
                    )
                    .opacity(isWordCardVisible ? 1 : 0.001)
                    .allowsHitTesting(isWordCardVisible)
                    .zIndex(1)
                }
            }
        }
        .coordinateSpace(name: progressRevealCoordinateSpace)
    }
}

private struct ProgressBucketSegmentedControl: View {
    let labels: [String]
    let selectedIndex: Int
    let selectedTextColor: Color
    let normalTextColor: Color
    let onSelect: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }
    private var containerBorderColor: Color {
        isDarkMode ? Color.white.opacity(0.12) : Color.white.opacity(0.54)
    }
    private var indicatorBorderColor: Color {
        isDarkMode ? Color.white.opacity(0.18) : Color.white.opacity(0.76)
    }
    private var clampedSelectedIndex: Int {
        guard !labels.isEmpty else { return 0 }
        return min(max(selectedIndex, 0), labels.count - 1)
    }

    var body: some View {
        GeometryReader { geo in
            let segmentTrackWidth = max(0, geo.size.width - 16)
            let segmentWidth = labels.isEmpty ? 0 : segmentTrackWidth / CGFloat(labels.count)
            let indicatorX = 8 + CGFloat(clampedSelectedIndex) * segmentWidth

            ZStack(alignment: .topLeading) {
                Group {
                    if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
                        Color.clear
                            .glassEffect(
                                .regular.interactive(),
                                in: Capsule(style: .continuous)
                            )
                    } else {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(indicatorBorderColor, lineWidth: 1)
                )
                .frame(width: segmentWidth, height: 46)
                .offset(x: indicatorX, y: 7)

                HStack(spacing: 0) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                        Button {
                            onSelect(idx)
                        } label: {
                            Text(label)
                                .font(.system(size: 18, weight: .semibold, design: .default))
                                .foregroundStyle(selectedIndex == idx ? selectedTextColor : normalTextColor)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            }
        }
        .frame(height: 60)
        .background {
            Group {
                if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular, in: Capsule(style: .continuous))
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        }
        .overlay(
            Capsule(style: .continuous)
                .stroke(containerBorderColor, lineWidth: 1)
        )
    }
}

private struct ProgressWordRow: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    let word: SimpleWord
    let onDelete: () -> Void
    let onTap: (CGPoint) -> Void

    private var translationText: String {
        appState.translationText(for: word)
    }
    private var isDarkMode: Bool { colorScheme == .dark }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(word.word)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(isDarkMode ? Color.white.opacity(0.86) : Color.black.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(2)

            Text(translationText)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(isDarkMode ? Color.white.opacity(0.58) : Color.black.opacity(0.44))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 205, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named(progressRevealCoordinateSpace))
                .onEnded { value in
                    onTap(value.location)
                }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(appState.localized("Delete", "删除", "हटाएं"), systemImage: "trash")
            }
            .tint(.red)
        }
    }
}

private struct SettingsScreen: View {
    @Binding private var pendingMemberPaywall: Bool
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var storeKitManager: StoreKitManager
    @EnvironmentObject private var srsManager: SRSManager
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    init(pendingMemberPaywall: Binding<Bool> = .constant(false)) {
        _pendingMemberPaywall = pendingMemberPaywall
    }
    @StateObject private var appIconManager = AppIconManager.shared
    @State private var showingAvatarPicker = false
    @State private var showingFAQ = false
    @State private var showingTermsOfUse = false
    @State private var showingShareSheet = false
    @State private var showingMemberUnlock = false
    @State private var memberPaywallShowingAllPlans = false
    @State private var showingAppIconPicker = false
    @State private var appIconErrorMessage: String?
    @State private var showingAppIconError = false
    @State private var showingResetLearningDataAlert = false
    @State private var avatarBottomGlobalY: CGFloat = 0
    @State private var themeSelectionOverride: Int?
    @State private var themeApplyTask: Task<Void, Never>?
    @AppStorage("dailyReminderEnabled") private var dailyReminderEnabled = false
    @AppStorage("dailyReminderHour") private var dailyReminderHour = 12
    @AppStorage("dailyReminderMinute") private var dailyReminderMinute = 0
    #if os(iOS)
    @State private var avatarImage: UIImage?
    @State private var avatarLoadTask: Task<Void, Never>?
    #endif

    private let levels = ["All", "A1", "A2", "B1", "B2", "C1", "C2"]
    private var levelLabels: [String] {
        [appState.localized("All", "全部", "सभी"), "A1", "A2", "B1", "B2", "C1", "C2"]
    }
    private let languageCodes = ["en", "zh", "hi"]
    private var languages: [String] { ["English", "中文", "हिन्दी"] }
    private let dailyCardLimits = [5, 10, 15, 20, 50]
    private var dailyCardLimitLabels: [String] { dailyCardLimits.map(String.init) }
    private let voiceOptions: [(id: String, name: String)] = [
        ("coral", "Coral"),
        ("alloy", "Alloy"),
        ("echo", "Echo"),
        ("shimmer", "Shimmer")
    ]
    private let appIconTileSize: CGFloat = 68
    private let developerContactEmail = "joey4wong@gmail.com"
    private let xProfileURL = "https://x.com/croissante4u?s=21"
    private let termsOfUseURL = "https://hungry-land-732.notion.site/Terms-of-Use-32c52d9458a9802e9308c296fc8fd9d8?source=copy_link"
    private let privacyPolicyURL = "https://hungry-land-732.notion.site/Privacy-Policy-32c52d9458a980b6975cd6786df84199?source=copy_link"
    private let cardFontOptions: [(style: CardFontStyle, label: String)] = [
        (.sfPro, "SF Pro"),
        (.sfRounded, "SF R"),
        (.avenirNext, "Avenir N"),
        (.newYork, "New York")
    ]
    private var appShareMessage: String {
        appState.localized(
            "I am learning French with Croissante. Join me!",
            "我正在用 Croissante 学法语，一起来！",
            "मैं Croissante के साथ फ्रेंच सीख रहा हूं, आप भी जुड़ें!"
        )
    }
    private var themes: [String] {
        [
            appState.localized("System", "跟随系统", "सिस्टम"),
            appState.localized("Light", "浅色", "लाइट"),
            appState.localized("Dark", "深色", "डार्क"),
            appState.localized("Steppe", "草原", "घासभूमि")
        ]
    }
    private let settingsToggleScale: CGFloat = 0.84
    private let settingsOptionRowVerticalPadding: CGFloat = 12
    private let settingsMenuControlHeight: CGFloat = 34
    private let chevronTrailingInset: CGFloat = 12
    private let appIconPickerDetentFraction: CGFloat = 0.5
    private let appIconPickerContentInset: CGFloat = 16
    private let appIconPickerBottomInset: CGFloat = 4

    private var appIconPickerLayout: AppIconPickerLayout {
        AppIconPickerLayout(
            tileSize: appIconTileSize,
            contentInset: appIconPickerContentInset,
            bottomInset: appIconPickerBottomInset,
            initialDropTopInset: 12,
            initialDropSpacing: 36
        )
    }

    private var selectedLevelIndex: Int {
        levels.firstIndex(of: appState.level) ?? 0
    }

    private var selectedLanguageIndex: Int {
        languageCodes.firstIndex(of: appState.language) ?? 0
    }

    private var selectedThemeIndex: Int {
        switch appState.themeMode {
        case .system: return 0
        case .light: return 1
        case .dark: return 2
        case .steppe: return 3
        }
    }

    private var displayedThemeIndex: Int {
        themeSelectionOverride ?? selectedThemeIndex
    }

    private var selectedDailyCardLimitIndex: Int {
        dailyCardLimits.firstIndex(of: srsManager.dailyDeckLimit) ?? (dailyCardLimits.count - 1)
    }

    private var selectedVoiceName: String {
        return voiceOptions.first(where: { $0.id == appState.selectedVoiceId })?.name ?? voiceOptions[0].name
    }
    private var selectedCardFontLabel: String {
        cardFontOptions.first(where: { $0.style == appState.cardFontStyle })?.label ?? cardFontOptions[0].label
    }
    private var notificationRowTitle: String {
        appState.localized("Reminders", "提醒", "रिमाइंडर")
    }
    private var reminderNotificationTitle: String {
        appState.localized("Time to learn French", "该学习法语了", "फ्रेंच सीखने का समय")
    }
    private var reminderNotificationBody: String {
        appState.localized(
            "Open Croissante and learn a few words today.",
            "打开 Croissante，开始今天的学习吧。",
            "Croissante खोलें और आज कुछ शब्द सीखें।"
        )
    }
    private var reminderToggleBinding: Binding<Bool> {
        Binding(
            get: { dailyReminderEnabled },
            set: { newValue in
                guard dailyReminderEnabled != newValue else { return }
                dailyReminderEnabled = newValue
                FeedbackService.toggleChanged(isOn: newValue)
                updateDailyReminderScheduling()
            }
        )
    }
    private var reminderStepIndex: Int {
        let hour = min(max(dailyReminderHour, 0), 23)
        let minute = min(max(dailyReminderMinute, 0), 59)
        let totalMinutes = hour * 60 + minute
        let snapped = Int(round(Double(totalMinutes) / 15.0))
        return min(max(snapped, 0), 95)
    }
    private var reminderTimeText: String {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = min(max(dailyReminderHour, 0), 23)
        components.minute = min(max(dailyReminderMinute, 0), 59)
        components.second = 0
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func setReminderStepIndex(_ index: Int) {
        let clamped = min(max(index, 0), 95)
        let totalMinutes = clamped * 15
        dailyReminderHour = totalMinutes / 60
        dailyReminderMinute = totalMinutes % 60
        updateDailyReminderScheduling()
    }

    private func updateDailyReminderScheduling() {
        let enabled = dailyReminderEnabled
        let hour = min(max(dailyReminderHour, 0), 23)
        let minute = min(max(dailyReminderMinute, 0), 59)
        let title = reminderNotificationTitle
        let body = reminderNotificationBody

        Task {
            let success = await DailyReminderService.shared.configure(
                enabled: enabled,
                hour: hour,
                minute: minute,
                title: title,
                body: body
            )
            if enabled && !success {
                await MainActor.run {
                    if dailyReminderEnabled {
                        dailyReminderEnabled = false
                    }
                }
            }
        }
    }

    private var spotlightToggleBinding: Binding<Bool> {
        Binding(
            get: { appState.spotlightEnabled },
            set: { newValue in
                guard appState.spotlightEnabled != newValue else { return }
                appState.spotlightEnabled = newValue
                FeedbackService.toggleChanged(isOn: newValue)
                if newValue {
                    SpotlightService.shared.indexAllWords(
                        appState.words,
                        conjugationFormsByLemma: appState.conjugationFormsByLemma
                    )
                } else {
                    SpotlightService.shared.removeAllWords()
                }
            }
        )
    }

    private var autoPlayToggleBinding: Binding<Bool> {
        Binding(
            get: { appState.autoPlay },
            set: { newValue in
                guard appState.autoPlay != newValue else { return }
                appState.autoPlay = newValue
                FeedbackService.toggleChanged(isOn: newValue)
            }
        )
    }

    private var iCloudSyncToggleBinding: Binding<Bool> {
        Binding(
            get: { appState.iCloudSyncEnabled },
            set: { newValue in
                guard appState.iCloudSyncEnabled != newValue else { return }
                appState.iCloudSyncEnabled = newValue
                FeedbackService.toggleChanged(isOn: newValue)
            }
        )
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private let memberPaywallCollapsedDetentHeight: CGFloat = 508
    private let memberPaywallExpandedDetentHeight: CGFloat = 618
    private var memberPaywallDetentHeight: CGFloat {
        memberPaywallShowingAllPlans ? memberPaywallExpandedDetentHeight : memberPaywallCollapsedDetentHeight
    }

    private func consumePendingMemberPaywallFromDeepLink() {
        guard pendingMemberPaywall else { return }
        pendingMemberPaywall = false
        guard !appState.memberUnlocked else { return }
        DispatchQueue.main.async {
            showingMemberUnlock = true
        }
    }

    private var avatarMetalRingGradient: [Color] {
        isDarkMode
            ? [
                Color(red: 0.92, green: 0.94, blue: 0.98).opacity(0.88),
                Color(red: 0.66, green: 0.70, blue: 0.78).opacity(0.78),
                Color(red: 0.35, green: 0.39, blue: 0.46).opacity(0.80),
                Color(red: 0.82, green: 0.86, blue: 0.94).opacity(0.90)
            ]
            : [
                Color(red: 0.98, green: 0.99, blue: 1.00).opacity(0.96),
                Color(red: 0.83, green: 0.86, blue: 0.91).opacity(0.90),
                Color(red: 0.60, green: 0.64, blue: 0.71).opacity(0.82),
                Color(red: 0.92, green: 0.94, blue: 0.98).opacity(0.94)
            ]
    }
    private var avatarMetalHighlight: Color {
        isDarkMode ? Color.white.opacity(0.58) : Color.white.opacity(0.82)
    }
    private var avatarMetalShadow: Color {
        isDarkMode ? Color.black.opacity(0.34) : Color.black.opacity(0.16)
    }
    // Match avatar -> member gap with member -> level options gap (which includes the level title block).
    private let memberGapCompensation: CGFloat = 18
    private var faqItems: [FAQItem] {
        [
            FAQItem(
                id: "dealing-cards",
                question: appState.localized(
                    "How do cards appear on the Explore screen?",
                    "首页的卡片是怎么出现的？",
                    "How do cards appear on the Explore screen?"
                ),
                answer: appState.localized(
                    "Cards are not pulled randomly one by one as you swipe. The app first builds a focused set of cards for today based on your current level and daily learning goal, then keeps guiding you through that set until today's learning is complete.",
                    "首页的学习卡片并不是在你每次滑动时临时随机抽取的。系统会先根据你当前选择的等级与每日学习目标，为你生成一组“今天要完成的卡片”，再围绕这组卡片持续推进当天的学习。",
                    "Cards are not pulled randomly one by one as you swipe. The app first builds a focused set of cards for today based on your current level and daily learning goal, then keeps guiding you through that set until today's learning is complete."
                )
            ),
            FAQItem(
                id: "daily-goal",
                question: appState.localized(
                    "What does a 5 / 10 / 15 daily goal mean?",
                    "“每日目标 5 / 10 / 15 张”是什么意思？",
                    "5 / 10 / 15 दैनिक लक्ष्य का क्या मतलब है?"
                ),
                answer: appState.localized(
                    "It is a today-pass goal, not a swipe count. Completion is measured by how many cards in today's target pool you can eventually mark Mastered today. That does not mean every card is permanently mastered in memory.",
                    "这代表“今日通过目标”，不是“滑动次数”。系统按“今天目标池里有多少张最终能被你标记为掌握”来判断完成度，但这不等于这些词已经在长期记忆里永久掌握。",
                    "It is a today-pass goal, not a swipe count. Completion is measured by how many cards in today's target pool you can eventually mark Mastered today. That does not mean every card is permanently mastered in memory."
                )
            ),
            FAQItem(
                id: "goal-upgrade",
                question: appState.localized(
                    "What happens if I change my daily goal or level during the day?",
                    "如果我在当天修改每日目标或等级，会发生什么？",
                    "What happens if I change my daily goal or level during the day?"
                ),
                answer: appState.localized(
                    "Changing either the daily goal or the level rebuilds today's study plan from scratch. The app generates a new target pool from your current level and current goal, clears today's completion progress, and recalculates today's heatmap from zero. If the rebuilt plan still has eligible cards, today usually goes back to the blinking green dot; if not, today stays gray in the no-eligible state.",
                    "只要你在当天修改每日目标或等级，系统就会把“今天的学习计划”整套重建。它会按你当前的等级和目标重新生成今天的目标池，清空今天的完成进度，并把今天的热力图按新计划从 0 重新计算。若重建后仍有可发卡，今天通常会回到闪烁的小绿点；若重建后没有可发卡，今天就会保持灰色，也就是“暂无可发卡”状态。",
                    "Changing either the daily goal or the level rebuilds today's study plan from scratch. The app generates a new target pool from your current level and current goal, clears today's completion progress, and recalculates today's heatmap from zero. If the rebuilt plan still has eligible cards, today usually goes back to the blinking green dot; if not, today stays gray in the no-eligible state."
                )
            ),
            FAQItem(
                id: "reappearing-card",
                question: appState.localized(
                    "Why does a card come back after I already swiped it away?",
                    "为什么我已经划走了一张卡，它后面又出现了？",
                    "Why does a card come back after I already swiped it away?"
                ),
                answer: appState.localized(
                    "After Blurry or Forgot, the card stays in today's target set until you can pass it today. If you later mark it Mastered on the same day, today's goal can move forward, but the long-term memory state stays unsettled and the word is scheduled for a short-term review.",
                    "当你标记“模糊/忘记”后，这张卡仍会留在今天的目标池里，直到你今天能把它通过。若你同一天后面又标记“掌握”，今日目标可以继续推进，但长期记忆状态仍会保留为未稳固，并安排短期复习。",
                    "After Blurry or Forgot, the card stays in today's target set until you can pass it today. If you later mark it Mastered on the same day, today's goal can move forward, but the long-term memory state stays unsettled and the word is scheduled for a short-term review."
                )
            ),
            FAQItem(
                id: "day-complete",
                question: appState.localized(
                    "When is today's Explore session actually complete?",
                    "首页什么时候才算完成？",
                    "When is today's Explore session actually complete?"
                ),
                answer: appState.localized(
                    "The day is complete when every card in today's base target pool has been passed today. A card that was Blurry or Forgot earlier can still count after you later mark it Mastered, but its Progress state may remain Blurry until a future review confirms it.",
                    "只有当“今天基础目标池”里的每张卡都在今天通过后，首页才算完成。某张卡今天早些时候被标记过“模糊/忘记”，后面再标记“掌握”也可以计入今日完成，但它在进度页里可能仍会保持“模糊”，直到未来复习再次确认。",
                    "The day is complete when every card in today's base target pool has been passed today. A card that was Blurry or Forgot earlier can still count after you later mark it Mastered, but its Progress state may remain Blurry until a future review confirms it."
                )
            ),
            FAQItem(
                id: "continue-infinity",
                question: appState.localized(
                    "What is Continue ∞ and when does it appear?",
                    "Continue ∞ 是什么？什么时候出现？",
                    "What is Continue ∞ and when does it appear?"
                ),
                answer: appState.localized(
                    "Continue ∞ appears only after you fully complete today's base mastery goal. It starts an optional extra-practice flow for your current level. Swipes there update memory state, progress buckets, and the next review schedule, but they do not change today's base completion or heatmap.",
                    "只有当你完整达成当天基础掌握目标后，首页才会出现 Continue ∞。点击后会进入“当前等级”的可选加练流。这里的滑动会写入记忆状态、进度分类和下次复习安排，但不会改动今日基础目标的完成状态或热力图。",
                    "Continue ∞ appears only after you fully complete today's base mastery goal. It starts an optional extra-practice flow for your current level. Swipes there update memory state, progress buckets, and the next review schedule, but they do not change today's base completion or heatmap."
                )
            ),
            FAQItem(
                id: "empty-state-meaning",
                question: appState.localized(
                    "What's the difference between 'goal complete' and 'no eligible cards'?",
                    "“今日完成”和“当前等级暂无可发卡”有什么区别？",
                    "What's the difference between 'goal complete' and 'no eligible cards'?"
                ),
                answer: appState.localized(
                    "'Goal complete' means you finished today's planned deck. 'No eligible cards' means that, for your current level right now, there are no new cards and no due reviews to issue.",
                    "“今日完成”表示你已完成今天计划牌堆；“当前等级暂无可发卡”表示按你当前等级与当前时点，既没有新词，也没有到期复习词可以发放。",
                    "'Goal complete' means you finished today's planned deck. 'No eligible cards' means that, for your current level right now, there are no new cards and no due reviews to issue."
                )
            ),
            FAQItem(
                id: "heatmap-color-levels",
                question: appState.localized(
                    "How does the heatmap color system work?",
                    "热力图的颜色等级是怎么计算的？",
                    "How does the heatmap color system work?"
                ),
                answer: appState.localized(
                    "The heatmap shows the state of that day's study plan, not raw swipe count. Deep green means completed. While in progress, 70%-99% is green, 20%-69% is light green, and below 20% only today's cell uses the blinking green dot. That blinking dot is only for today; after the day passes, progress below 20% is no longer highlighted and the cell appears gray. Gray also covers days with no eligible cards.",
                    "热力图显示的是“当天学习计划的状态”，不是单纯的滑动次数。深绿表示已完成；进行中时，70%-99% 显示绿色，20%-69% 显示浅绿，低于 20% 时只有今天这一天会显示闪烁的小绿点。这个闪烁点只用于今天；一旦过了今天，低于 20% 的进度不再单独高亮，会显示为灰色。灰色也包括当天本来就没有可发卡的情况。",
                    "The heatmap shows the state of that day's study plan, not raw swipe count. Deep green means completed. While in progress, 70%-99% is green, 20%-69% is light green, and below 20% only today's cell uses the blinking green dot. That blinking dot is only for today; after the day passes, progress below 20% is no longer highlighted and the cell appears gray. Gray also covers days with no eligible cards."
                )
            ),
            FAQItem(
                id: "new-vs-review",
                question: appState.localized(
                    "How are new cards and review cards balanced?",
                    "新词和复习词是如何分配的？",
                    "How are new cards and review cards balanced?"
                ),
                answer: appState.localized(
                    "Due review cards are prioritized first. The scheduler targets a 20% new-card quota when enough new words are available; if not, those slots are backfilled by due reviews (and vice versa).",
                    "系统会先保证到期复习词优先。新词方面，调度器会在“新词库存充足”时尽量保留 20% 名额；若新词不足，会由到期复习词回填（反之亦然）。",
                    "Due review cards are prioritized first. The scheduler targets a 20% new-card quota when enough new words are available; if not, those slots are backfilled by due reviews (and vice versa)."
                )
            ),
            FAQItem(
                id: "review-order",
                question: appState.localized(
                    "How does the app choose which review cards come first?",
                    "复习词是按什么顺序进入今天任务的？",
                    "How does the app choose which review cards come first?"
                ),
                answer: appState.localized(
                    "Review cards are chosen by urgency. Words that became due earlier, and have been waiting longer, are pulled into today's target pool first so the most time-sensitive reviews are handled before newer ones.",
                    "系统会优先选择那些更早到期、也更久没有复习的单词。换句话说，越应该被及时复习的词，越会优先进入你今天的学习任务。",
                    "Review cards are chosen by urgency. Words that became due earlier, and have been waiting longer, are pulled into today's target pool first so the most time-sensitive reviews are handled before newer ones."
                )
            ),
            FAQItem(
                id: "swipe-meanings",
                question: appState.localized(
                    "What do Mastered, Blurry, and Forgot each mean?",
                    "“掌握”“模糊”“忘记”分别会带来什么影响？",
                    "What do Mastered, Blurry, and Forgot each mean?"
                ),
                answer: appState.localized(
                    "On today's base deck, swipe right means passed today, swipe down is Blurry, swipe left is Forgot, and swipe up does nothing. Progress uses long-term memory state: if a word was Blurry or Forgot earlier today, a later right swipe completes today's card but keeps it unsettled for review.",
                    "在今天的基础牌堆里，右滑表示“今天通过”，下滑是“模糊”，左滑是“忘记”，上滑不记录任何操作。进度页看的是长期记忆状态：如果一个词今天早些时候被标记过“模糊/忘记”，后面再右滑可以完成今日卡片，但它仍会保持未稳固并等待复习。",
                    "On today's base deck, swipe right means passed today, swipe down is Blurry, swipe left is Forgot, and swipe up does nothing. Progress uses long-term memory state: if a word was Blurry or Forgot earlier today, a later right swipe completes today's card but keeps it unsettled for review."
                )
            ),
            FAQItem(
                id: "blurry-forgot-review",
                question: appState.localized(
                    "How do Blurry and Forgot affect reviews?",
                    "“模糊”和“忘记”会怎样影响复习？",
                    "Blurry और Forgot से रिव्यू कैसे बदलता है?"
                ),
                answer: appState.localized(
                    "Blurry and Forgot do not add extra cards to today's goal. The word stays in today's set until you can mark it Mastered, and both are scheduled for a short review tomorrow. Forgot resets consecutive corrects to 0; Blurry only reduces them by 1. If you mark it Mastered later on the same day, today's goal can count it as passed, but long-term progress still treats it as unsettled. It returns to Mastered only after a later scheduled review is also marked Mastered.",
                    "“模糊”和“忘记”不会给今天额外加卡。这个词会留在今天的目标池里，直到你今天把它标记为“掌握”；两者都会安排到明天短期复习。区别是：“忘记”会把连续正确数归 0，“模糊”只会让连续正确数减 1。如果同一天后面又标记“掌握”，今天的目标可以把它算作通过，但长期进度仍会把它视为未稳固；只有之后到期复习也标记“掌握”，它才会真正回到“掌握”。",
                    "Blurry और Forgot आज के लक्ष्य में अतिरिक्त कार्ड नहीं जोड़ते। शब्द आज के सेट में तब तक रहता है जब तक आप उसे Mastered नहीं कर देते, और दोनों को कल छोटे रिव्यू के लिए रखा जाता है। Forgot लगातार सही जवाबों को 0 कर देता है; Blurry उन्हें सिर्फ 1 घटाता है। अगर आप उसी दिन बाद में Mastered कर दें, तो आज का लक्ष्य उसे पास मान सकता है, लेकिन लंबी अवधि की प्रगति उसे अभी भी अस्थिर मानती है। वह बाद की scheduled review में फिर से Mastered होने पर ही Mastered में लौटता है."
                )
            ),
            FAQItem(
                id: "progress-buckets",
                question: appState.localized(
                    "Why can a word stay Blurry after I mark it Mastered?",
                    "为什么我点了“掌握”，它还会留在“模糊”？",
                    "Why can a word stay Blurry after I mark it Mastered?"
                ),
                answer: appState.localized(
                    "Because Progress is not a last-swipe list. If a word was missed today, the same-day Mastered swipe only proves you can pass it after practice. The word moves back to Mastered after a later scheduled review also succeeds.",
                    "因为进度页不是“最后一次手势列表”。如果一个词今天出错过，同一天后面的“掌握”只能说明你通过练习后暂时答对了；等后续到期复习再次成功，它才会回到“掌握”。",
                    "Because Progress is not a last-swipe list. If a word was missed today, the same-day Mastered swipe only proves you can pass it after practice. The word moves back to Mastered after a later scheduled review also succeeds."
                )
            ),
            FAQItem(
                id: "random-feel",
                question: appState.localized(
                    "Why does Explore feel a little random but not completely random?",
                    "为什么首页看起来有一点随机，但又不像完全随机？",
                    "Why does Explore feel a little random but not completely random?"
                ),
                answer: appState.localized(
                    "Because the system first decides very carefully which words deserve to be in today's learning set, then shuffles how those selected cards are shown. The experience feels natural and light, but the scheduling underneath is still deliberate and structured.",
                    "因为系统会先严格决定“哪些词应该进入今天的学习任务”，再将这些入选卡片自然打散展示。你看到的是更轻松的学习节奏，但背后仍然遵循清晰的记忆调度逻辑。",
                    "Because the system first decides very carefully which words deserve to be in today's learning set, then shuffles how those selected cards are shown. The experience feels natural and light, but the scheduling underneath is still deliberate and structured."
                )
            )
        ]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 22) {
                Spacer().frame(height: 16)

                Button {
                    showingAvatarPicker = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(isDarkMode ? Color.white.opacity(0.14) : Color.white.opacity(0.55))
                            .frame(width: 100, height: 100)
                        #if os(iOS)
                        if let img = avatarImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(isDarkMode ? Color.white.opacity(0.55) : Color.black.opacity(0.36))
                        }
                        #else
                        Image(systemName: "person.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(isDarkMode ? Color.white.opacity(0.55) : Color.black.opacity(0.36))
                        #endif
                        Circle()
                            .stroke(isDarkMode ? Color.white.opacity(0.22) : Color.white.opacity(0.6), lineWidth: 2)
                            .frame(width: 100, height: 100)
                        Circle()
                            .strokeBorder(
                                AngularGradient(colors: avatarMetalRingGradient, center: .center),
                                lineWidth: 4
                            )
                            .frame(width: 94, height: 94)
                            .shadow(color: avatarMetalShadow, radius: 1.5, x: 0, y: 1)
                            .overlay(
                                Circle()
                                    .trim(from: 0.08, to: 0.36)
                                    .stroke(
                                        avatarMetalHighlight,
                                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-20))
                                    .frame(width: 90, height: 90)
                            )
                    }
                }
                .buttonStyle(.plain)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: SettingsAvatarBottomPreferenceKey.self,
                            value: geo.frame(in: .global).maxY
                        )
                    }
                )
                .sheet(isPresented: $showingAvatarPicker) {
                    AvatarEditorView()
                        .environmentObject(appState)
                        #if os(iOS)
                        .presentationDetents([.height(204)])
                        .presentationDragIndicator(.visible)
                        #endif
                }
                .onAppear {
                    refreshAvatarImage()
                    updateDailyReminderScheduling()
                }
                .onChange(of: appState.avatarPath) { _, _ in
                    refreshAvatarImage()
                }
                .onDisappear {
                    cancelAvatarImageLoading()
                }

                if storeKitManager.purchasedProduct != .some(.lifetime) {
                    SettingsGroupCard {
                        Button {
                            showingMemberUnlock = true
                        } label: {
                            SettingsCardRow(
                                icon: "crown",
                                title: "Croissante Plus",
                                subtitle: "",
                                titleFontSize: 13,
                                rowVerticalPadding: settingsOptionRowVerticalPadding,
                                showsSubtitle: false,
                                showsDivider: false,
                                matchPickerFont: true
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.42) : Color.black.opacity(0.30))
                                    .frame(width: 44, height: settingsMenuControlHeight, alignment: .center)
                                    .padding(.trailing, chevronTrailingInset)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 22)
                    .padding(.horizontal, 20)
                }

                SettingsGroupCard {
                        SettingsCardRow(
                            icon: "chart.bar.fill",
                            title: appState.localized("Level", "等级", "स्तर"),
                            subtitle: "",
                            titleFontSize: 13,
                            rowVerticalPadding: settingsOptionRowVerticalPadding,
                            showsSubtitle: false,
                            showsDivider: true,
                            matchPickerFont: true
                        ) {
                            Picker(
                                levelLabels[selectedLevelIndex],
                                selection: Binding(
                                    get: { selectedLevelIndex },
                                    set: { appState.level = levels[$0] }
                                )
                            ) {
                                ForEach(0..<levels.count, id: \.self) { i in
                                    Text(levelLabels[i]).tag(i)
                                }
                            }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .pickerStyle(.menu)
                            .tint(isDarkMode ? Color.white.opacity(0.52) : Color.black.opacity(0.44))
                            .lineLimit(1)
                            .minimumScaleFactor(0.88)
                            .frame(minWidth: 112, alignment: .trailing)
                            .frame(height: settingsMenuControlHeight, alignment: .center)
                        }

                        SettingsCardRow(
                            icon: "flame.fill",
                            title: appState.localized("Daily Goal", "每日目标", "दैनिक लक्ष्य"),
                            subtitle: "",
                            titleFontSize: 13,
                            rowVerticalPadding: settingsOptionRowVerticalPadding,
                            showsSubtitle: false,
                            showsDivider: true,
                            matchPickerFont: true
                        ) {
                            Picker(
                                dailyCardLimitLabels[selectedDailyCardLimitIndex],
                                selection: Binding(
                                    get: { selectedDailyCardLimitIndex },
                                    set: { srsManager.setDailyDeckLimit(dailyCardLimits[$0]) }
                                )
                            ) {
                                ForEach(0..<dailyCardLimits.count, id: \.self) { i in
                                    Text(dailyCardLimitLabels[i]).tag(i)
                                }
                            }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .pickerStyle(.menu)
                            .tint(isDarkMode ? Color.white.opacity(0.52) : Color.black.opacity(0.44))
                            .frame(height: settingsMenuControlHeight, alignment: .center)
                        }

                        if appState.memberUnlocked {
                            SettingsCardRow(
                                icon: "waveform",
                                title: appState.localized("Natural Voice", "自然语音", "प्राकृतिक आवाज़"),
                                subtitle: "",
                                titleFontSize: 13,
                                rowVerticalPadding: settingsOptionRowVerticalPadding,
                                showsSubtitle: false,
                                showsDivider: false,
                                matchPickerFont: true
                            ) {
                                Picker(
                                    selectedVoiceName,
                                    selection: Binding(
                                        get: { appState.selectedVoiceId },
                                        set: { appState.selectedVoiceId = $0 }
                                    )
                                ) {
                                    ForEach(voiceOptions, id: \.id) { option in
                                        Text(option.name).tag(option.id)
                                    }
                                }
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .pickerStyle(.menu)
                                .tint(isDarkMode ? Color.white.opacity(0.52) : Color.black.opacity(0.44))
                                .frame(height: settingsMenuControlHeight, alignment: .center)
                            }
                        } else {
                            Button {
                                showingMemberUnlock = true
                            } label: {
                                SettingsCardRow(
                                    icon: "waveform",
                                    title: appState.localized("Natural Voice", "自然语音", "प्राकृतिक आवाज़"),
                                    subtitle: "",
                                    titleFontSize: 13,
                                    rowVerticalPadding: settingsOptionRowVerticalPadding,
                                    showsSubtitle: false,
                                    showsDivider: false,
                                    matchPickerFont: true
                                ) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.32))
                                        .frame(width: 44, height: settingsMenuControlHeight, alignment: .center)
                                        .padding(.trailing, chevronTrailingInset)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                }
                .padding(.horizontal, 20)

                SettingsGroupCard {
                        SettingsCardRow(
                            icon: "globe",
                            title: appState.localized("Language", "语言", "भाषा"),
                            subtitle: "",
                            titleFontSize: 13,
                            rowVerticalPadding: settingsOptionRowVerticalPadding,
                            showsSubtitle: false,
                            showsDivider: true,
                            matchPickerFont: true
                        ) {
                            Picker(
                                languages[selectedLanguageIndex],
                                selection: Binding(
                                    get: { appState.language },
                                    set: { appState.language = $0 }
                                )
                            ) {
                                ForEach(0..<languageCodes.count, id: \.self) { i in
                                    Text(languages[i]).tag(languageCodes[i])
                                }
                            }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .pickerStyle(.menu)
                            .tint(isDarkMode ? Color.white.opacity(0.52) : Color.black.opacity(0.44))
                            .frame(height: settingsMenuControlHeight, alignment: .center)
                        }

                        SettingsCardRow(
                            icon: "paintbrush.fill",
                            title: appState.localized("Theme", "主题", "थीम"),
                            subtitle: "",
                            titleFontSize: 13,
                            rowVerticalPadding: settingsOptionRowVerticalPadding,
                            showsSubtitle: false,
                            showsDivider: true,
                            matchPickerFont: true
                        ) {
                            Picker(
                                themes[displayedThemeIndex],
                                selection: Binding(
                                    get: { displayedThemeIndex },
                                    set: { idx in
                                        let newMode: ThemeMode
                                        switch idx {
                                        case 0: newMode = .system
                                        case 1: newMode = .light
                                        case 2: newMode = .dark
                                        default: newMode = .steppe
                                        }
                                        guard appState.themeMode != newMode || themeSelectionOverride != nil else { return }
                                        themeSelectionOverride = idx
                                        themeApplyTask?.cancel()
                                        themeApplyTask = Task { @MainActor in
                                            try? await Task.sleep(nanoseconds: 180_000_000)
                                            guard !Task.isCancelled else { return }
                                            appState.themeMode = newMode
                                        }
                                    }
                                )
                            ) {
                                ForEach(0..<themes.count, id: \.self) { i in
                                    Text(themes[i]).tag(i)
                                }
                            }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .pickerStyle(.menu)
                            .tint(isDarkMode ? Color.white.opacity(0.52) : Color.black.opacity(0.44))
                            .frame(height: settingsMenuControlHeight, alignment: .center)
                        }

                        SettingsCardRow(
                            icon: "textformat",
                            title: appState.localized("Card Font", "卡片字体", "कार्ड फ़ॉन्ट"),
                            subtitle: "",
                            titleFontSize: 13,
                            rowVerticalPadding: settingsOptionRowVerticalPadding,
                            showsSubtitle: false,
                            showsDivider: true,
                            matchPickerFont: true
                        ) {
                            Picker(
                                selectedCardFontLabel,
                                selection: Binding(
                                    get: { appState.cardFontStyle },
                                    set: { appState.cardFontStyle = $0 }
                                )
                            ) {
                                ForEach(cardFontOptions, id: \.style) { option in
                                    Text(option.label).tag(option.style)
                                }
                            }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .pickerStyle(.menu)
                            .tint(isDarkMode ? Color.white.opacity(0.52) : Color.black.opacity(0.44))
                            .frame(height: settingsMenuControlHeight, alignment: .center)
                        }

                        appIconOptionsSection
                }
                .padding(.horizontal, 20)

                SettingsGroupCard {
                        SettingsCardRow(
                            icon: "magnifyingglass",
                            title: appState.localized("Spotlight Search", "聚焦搜索", "स्पॉटलाइट खोज"),
                            subtitle: appState.localized("Search words from iOS Spotlight", "在 iOS 聚焦中搜索单词", "iOS स्पॉटलाइट में शब्द खोजें"),
                            titleFontSize: 13,
                            rowVerticalPadding: settingsOptionRowVerticalPadding,
                            showsDivider: true,
                            matchPickerFont: true
                        ) {
                            Toggle("", isOn: spotlightToggleBinding)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                                .scaleEffect(settingsToggleScale)
                                .frame(height: settingsMenuControlHeight, alignment: .center)
                        }

                        SettingsCardRow(
                            icon: "icloud",
                            title: appState.localized("iCloud Sync", "iCloud 同步", "iCloud सिंक"),
                            subtitle: appState.localized(
                                "Sync learning progress across your devices",
                                "在你的设备间同步学习进度",
                                "अपने सभी डिवाइस में सीखने की प्रगति सिंक करें"
                            ),
                            titleFontSize: 13,
                            rowVerticalPadding: settingsOptionRowVerticalPadding,
                            showsDivider: true,
                            matchPickerFont: true
                        ) {
                            Toggle("", isOn: iCloudSyncToggleBinding)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                                .scaleEffect(settingsToggleScale)
                                .frame(height: settingsMenuControlHeight, alignment: .center)
                        }

                        SettingsCardRow(
                            icon: "speaker.wave.2.fill",
                            title: appState.localized("Auto-play", "自动播放", "ऑटो-प्ले"),
                            subtitle: appState.localized("Speak the word automatically", "自动朗读单词", "शब्द अपने आप बोलें"),
                            titleFontSize: 13,
                            rowVerticalPadding: settingsOptionRowVerticalPadding,
                            showsDivider: true,
                            matchPickerFont: true
                        ) {
                            Toggle("", isOn: autoPlayToggleBinding)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                                .scaleEffect(settingsToggleScale)
                                .frame(height: settingsMenuControlHeight, alignment: .center)
                        }

                        Button {
                            showingResetLearningDataAlert = true
                        } label: {
                            SettingsCardRow(
                                icon: "arrow.counterclockwise.circle.fill",
                                title: appState.localized("Reset Data", "重置数据", "डेटा रीसेट"),
                                subtitle: appState.localized("Reset learning progress", "重置学习进度", "सीखने की प्रगति रीसेट करें"),
                                titleFontSize: 13,
                                rowVerticalPadding: settingsOptionRowVerticalPadding,
                                showsSubtitle: false,
                                showsDivider: false,
                                matchPickerFont: true
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.42) : Color.black.opacity(0.30))
                                    .frame(width: 44, height: settingsMenuControlHeight, alignment: .center)
                                    .padding(.trailing, chevronTrailingInset)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                .padding(.horizontal, 20)

                SettingsGroupCard {
                    NotificationReminderSettingsCard(
                        title: notificationRowTitle,
                        displayTime: reminderTimeText,
                        stepIndex: reminderStepIndex,
                        isEnabled: reminderToggleBinding,
                        onChangeStep: setReminderStepIndex
                    )
                }
                .padding(.horizontal, 20)

                SettingsGroupCard {
                        Button {
                            showingFAQ = true
                        } label: {
                            SettingsCardRow(
                                icon: "questionmark.circle",
                                title: appState.localized("FAQ", "常见问题", "सामान्य प्रश्न"),
                                subtitle: appState.localized("Frequently asked questions", "常见问题解答", "अक्सर पूछे जाने वाले सवाल"),
                                titleFontSize: 13,
                                rowVerticalPadding: settingsOptionRowVerticalPadding,
                                showsDivider: true,
                                matchPickerFont: true
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.42) : Color.black.opacity(0.30))
                                    .frame(width: 44, height: settingsMenuControlHeight, alignment: .center)
                                    .padding(.trailing, chevronTrailingInset)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            if let url = URL(string: termsOfUseURL) {
                                openURL(url)
                            }
                        } label: {
                            SettingsCardRow(
                                icon: "doc.text",
                                title: appState.localized("Terms of Use", "使用条款", "उपयोग की शर्तें"),
                                subtitle: appState.localized("Terms and conditions", "条款与条件", "नियम और शर्तें"),
                                titleFontSize: 13,
                                rowVerticalPadding: settingsOptionRowVerticalPadding,
                                showsDivider: true,
                                matchPickerFont: true
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.42) : Color.black.opacity(0.30))
                                    .frame(width: 44, height: settingsMenuControlHeight, alignment: .center)
                                    .padding(.trailing, chevronTrailingInset)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            if let url = URL(string: privacyPolicyURL) {
                                openURL(url)
                            }
                        } label: {
                            SettingsCardRow(
                                icon: "shield",
                                title: appState.localized("Privacy Policy", "隐私政策", "गोपनीयता नीति"),
                                subtitle: appState.localized("How we handle your data", "我们如何处理你的数据", "हम आपके डेटा को कैसे संभालते हैं"),
                                titleFontSize: 13,
                                rowVerticalPadding: settingsOptionRowVerticalPadding,
                                showsDivider: false,
                                matchPickerFont: true
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.42) : Color.black.opacity(0.30))
                                    .frame(width: 44, height: settingsMenuControlHeight, alignment: .center)
                                    .padding(.trailing, chevronTrailingInset)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                .padding(.horizontal, 20)

                SettingsGroupCard {
                        SettingsCardRow(
                            icon: "swirl.circle.righthalf.filled",
                            iconAssetName: "croissante_dev_icon",
                            title: "Croissante",
                            subtitle: appState.localized("One croissant a day, one French word away", "可颂天天有，法语天天懂。", "हर दिन एक क्रोइसां, एक फ़्रेंच शब्द"),
                            titleFontSize: 13,
                            rowVerticalPadding: 12,
                            showsSubtitle: true,
                            showsDivider: false
                        ) {
                            EmptyView()
                        }

                        SettingsActionButtonsRow(
                            labels: [
                                "SF:flag.circle.fill",
                                "X",
                                "SF:star.leadinghalf.filled",
                                "SF:square.and.arrow.up.circle"
                            ],
                            accessibilityLabels: [
                                appState.localized("Report", "报错", "रिपोर्ट"),
                                "X",
                                appState.localized("Rate", "评分", "रेट"),
                                appState.localized("Share", "分享", "शेयर")
                            ]
                        ) { index in
                            switch index {
                            case 0:
                                contactDeveloper()
                            case 1:
                                openXProfile()
                            case 2:
                                requestAppStoreRating()
                            case 3:
                                #if os(iOS)
                                showingShareSheet = true
                                #endif
                            default:
                                break
                            }
                        }
                    }
                .padding(.horizontal, 20)

                settingsBrandFooter
                    .padding(.horizontal, 20)

                Spacer(minLength: 24)
            }
        }
        .onPreferenceChange(SettingsAvatarBottomPreferenceKey.self) { y in
            avatarBottomGlobalY = y
        }
        .sheet(isPresented: $showingMemberUnlock, onDismiss: {
            memberPaywallShowingAllPlans = false
        }) {
            MemberUnlockPaywallView(showingAllPlans: $memberPaywallShowingAllPlans)
                .environmentObject(appState)
                .environmentObject(storeKitManager)
            #if os(iOS)
                .presentationDetents([.height(memberPaywallDetentHeight)])
                .presentationDragIndicator(.visible)
            #endif
        }
        .onChange(of: pendingMemberPaywall) { _, _ in
            consumePendingMemberPaywallFromDeepLink()
        }
        .onAppear {
            consumePendingMemberPaywallFromDeepLink()
        }
        .sheet(isPresented: $showingAppIconPicker) {
            appIconPickerSheet
                .environmentObject(appState)
            #if os(iOS)
                .presentationDetents([.fraction(appIconPickerDetentFraction)])
                .presentationDragIndicator(.visible)
            #endif
        }
        .sheet(isPresented: $showingFAQ) {
            FAQSheetView(items: faqItems)
                .environmentObject(appState)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
        .sheet(isPresented: $showingTermsOfUse) {
            LegalDocumentSheetView(
                themeMode: appState.themeMode,
                title: appState.localized("Terms of Use", "使用条款", "उपयोग की शर्तें"),
                subtitle: appState.localized(
                    "Please review these terms before using the app.",
                    "使用应用前，请先阅读以下条款。",
                    "Please review these terms before using the app."
                ),
                paragraphs: [
                    appState.localized(
                        "Croissante is designed for personal language learning. You are responsible for how you use the content and learning suggestions in your own study routine.",
                        "Croissante 用于个人语言学习。你需要根据自己的学习情况判断并使用应用中的内容与学习建议。",
                        "Croissante is designed for personal language learning. You are responsible for how you use the content and learning suggestions in your own study routine."
                    ),
                    appState.localized(
                        "Features and wording may evolve over time as the learning model improves. Continued use means you agree with these product updates.",
                        "随着学习模型持续优化，功能和文案可能会调整。继续使用即表示你接受这些产品更新。",
                        "Features and wording may evolve over time as the learning model improves. Continued use means you agree with these product updates."
                    ),
                    appState.localized(
                        "If you have questions about account behavior, progress data, or feature access, please contact support from the developer section.",
                        "如对账户行为、学习进度数据或功能访问有疑问，请通过开发者页面的联系方式与我们沟通。",
                        "If you have questions about account behavior, progress data, or feature access, please contact support from the developer section."
                    )
                ]
            )
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showingShareSheet) {
            ActivityShareSheet(activityItems: [appShareMessage])
        }
        #endif
        .alert(
            appState.localized("Unable to Change Icon", "图标切换失败", "आइकन बदलना असफल"),
            isPresented: $showingAppIconError
        ) {
            Button(appState.localized("OK", "好的", "ठीक है"), role: .cancel) {}
        } message: {
            Text(appIconErrorMessage ?? appState.localized("Please try again later.", "请稍后再试。", "कृपया बाद में फिर कोशिश करें।"))
        }
        .alert(
            appState.localized("Reset Learning Data", "重置学习数据", "सीखने का डेटा रीसेट करें"),
            isPresented: $showingResetLearningDataAlert
        ) {
            Button(appState.localized("Cancel", "取消", "रद्द करें"), role: .cancel) {}
            Button(appState.localized("Reset", "重置", "रीसेट"), role: .destructive) {
                resetLearningData()
            }
        } message: {
            Text(
                appState.localized(
                    "This will clear your learning progress and cannot be undone.",
                    "这会清空你的学习进度，且无法撤销。",
                    "यह आपकी सीखने की प्रगति साफ कर देगा और इसे वापस नहीं किया जा सकता।"
                )
            )
        }
        .onAppear {
            syncAppIconState()
        }
        .onChange(of: appState.themeMode) { _, _ in
            guard let themeSelectionOverride else { return }
            if themeSelectionOverride == selectedThemeIndex {
                self.themeSelectionOverride = nil
            }
        }
        .onDisappear {
            themeApplyTask?.cancel()
            themeApplyTask = nil
            themeSelectionOverride = nil
        }
    }

    @MainActor
    private func refreshAvatarImage() {
        #if os(iOS)
        avatarLoadTask?.cancel()
        let currentPath = appState.avatarPath
        guard !currentPath.isEmpty else {
            avatarImage = nil
            return
        }

        avatarLoadTask = Task(priority: .utility) { [currentPath] in
            let loaded = await loadAvatarImageAsync(from: currentPath)
            guard !Task.isCancelled else { return }
            guard appState.avatarPath == currentPath else { return }
            avatarImage = loaded
        }
        #endif
    }

    @MainActor
    private func cancelAvatarImageLoading() {
        #if os(iOS)
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        #endif
    }

    private func contactDeveloper() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = developerContactEmail
        components.queryItems = [
            URLQueryItem(
                name: "subject",
                value: appState.localized("Croissante Feedback", "Croissante 反馈", "Croissante प्रतिक्रिया")
            )
        ]
        guard let url = components.url else { return }
        openURL(url)
    }

    private func openXProfile() {
        guard let url = URL(string: xProfileURL) else { return }
        openURL(url)
    }

    private func requestAppStoreRating() {
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }
        AppStore.requestReview(in: scene)
        #endif
    }

    private func resetLearningData() {
        srsManager.resetLearningData()
        UserDefaults.standard.removeObject(forKey: "search_recent_word_ids")
        themeApplyTask?.cancel()
        themeSelectionOverride = nil
        appState.themeMode = .system
    }

    private var settingsBrandFooter: some View {
        HStack(spacing: 8) {
            Image("SettingsFooterBrand")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text("Croissante")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.62) : Color.black.opacity(0.54))

                Text("Version 1.0")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.36) : Color.black.opacity(0.34))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var appIconOptionsSection: some View {
        Button {
            if appState.memberUnlocked {
                showingAppIconPicker = true
            } else {
                showingMemberUnlock = true
            }
        } label: {
            SettingsCardRow(
                icon: "swirl.circle.righthalf.filled",
                iconAssetName: "croissante_dev_icon",
                title: appState.localized("App Icon", "应用图标", "ऐप आइकन"),
                subtitle: "",
                titleFontSize: 13,
                rowVerticalPadding: settingsOptionRowVerticalPadding,
                showsDivider: false,
                matchPickerFont: true
            ) {
                Image(systemName: appState.memberUnlocked ? "chevron.right" : "lock.fill")
                    .font(.system(size: appState.memberUnlocked ? 18 : 14, weight: appState.memberUnlocked ? .medium : .semibold))
                    .foregroundStyle(
                        appState.memberUnlocked
                            ? (isDarkMode ? Color.white.opacity(0.42) : Color.black.opacity(0.30))
                            : (isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.32))
                    )
                    .frame(width: 44, height: settingsMenuControlHeight, alignment: .center)
                    .padding(.trailing, chevronTrailingInset)
            }
        }
        .buttonStyle(.plain)
    }

    private var appIconPickerSheet: some View {
        Group {
            #if os(iOS)
            AppIconPhysicsPicker(
                icons: AppIconManager.AppIcon.allIcons,
                currentIconID: appIconManager.currentIcon.id,
                memberUnlocked: appState.memberUnlocked,
                isDarkMode: isDarkMode,
                isApplying: appIconManager.changingIcon,
                layout: appIconPickerLayout,
                onTapIcon: handleAppIconSelection
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .ignoresSafeArea(.container, edges: .bottom)
            .padding(appIconPickerLayout.sheetInsets)
            #else
            GeometryReader { proxy in
                let horizontalSpacing = max((proxy.size.width - appIconTileSize * 3) / 4, 0)
                let columns = Array(
                    repeating: GridItem(.fixed(appIconTileSize), spacing: horizontalSpacing, alignment: .center),
                    count: 3
                )

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(AppIconManager.AppIcon.allIcons) { icon in
                            appIconTile(icon)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                    .padding(.horizontal, horizontalSpacing)
                    .padding(.vertical, 8)
                }
            }
            #endif
        }
    }

    private func handleAppIconSelection(_ icon: AppIconManager.AppIcon) {
        let isMemberIcon = !AppIconManager.AppIcon.freeIconIDs.contains(icon.id)
        let isLocked = isMemberIcon && !appState.memberUnlocked

        showingAppIconPicker = false

        if isLocked {
            presentMemberUnlockAfterClosingIconPicker()
            return
        }

        applyAppIcon(icon)
    }

    private func appIconTile(_ icon: AppIconManager.AppIcon) -> some View {
        let isSelected = appIconManager.currentIcon.id == icon.id
        let isMemberIcon = !AppIconManager.AppIcon.freeIconIDs.contains(icon.id)
        let isLocked = isMemberIcon && !appState.memberUnlocked
        let borderColor = isSelected
            ? (isDarkMode ? Color.white.opacity(0.6) : Color.black.opacity(0.35))
            : (isDarkMode ? Color.white.opacity(0.16) : Color.black.opacity(0.10))
        let borderWidth = isSelected ? 1.5 : 1.0

        return Button {
            handleAppIconSelection(icon)
        } label: {
            Image(icon.previewAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: appIconTileSize, height: appIconTileSize)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                .overlay(alignment: .topTrailing) {
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isDarkMode ? Color.white.opacity(0.92) : Color.black.opacity(0.86))
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(isDarkMode ? Color.black.opacity(0.68) : Color.white.opacity(0.9))
                            )
                            .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(appIconManager.changingIcon || (!isLocked && isSelected))
        .opacity(appIconManager.changingIcon && !isSelected ? 0.6 : 1)
    }

    private func presentMemberUnlockAfterClosingIconPicker() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            showingMemberUnlock = true
        }
    }

    @MainActor
    private func syncAppIconState() {
        appIconManager.refreshCurrentIcon()
        appState.appIconName = appIconManager.currentIcon.iconName
    }

    private func applyAppIcon(_ icon: AppIconManager.AppIcon) {
        Task { @MainActor in
            if appIconManager.currentIcon.id == icon.id {
                return
            }
            do {
                try await appIconManager.changeIcon(to: icon)
                appState.appIconName = icon.iconName
            } catch {
                appIconErrorMessage = error.localizedDescription
                showingAppIconError = true
            }
        }
    }

    #if os(iOS)
    private func loadAvatarImageAsync(from path: String) async -> UIImage? {
        ImagePickerService.shared.loadImageFromPath(path)
    }
    #endif
}

#if os(iOS)
private struct AppIconPhysicsPicker: UIViewRepresentable {
    let icons: [AppIconManager.AppIcon]
    let currentIconID: String
    let memberUnlocked: Bool
    let isDarkMode: Bool
    let isApplying: Bool
    let layout: AppIconPickerLayout
    let onTapIcon: (AppIconManager.AppIcon) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> AppIconPhysicsContainerView {
        let view = AppIconPhysicsContainerView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: AppIconPhysicsContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyCurrentState(animated: true)
    }

    final class Coordinator: NSObject, UICollisionBehaviorDelegate {
        var parent: AppIconPhysicsPicker
        weak var container: AppIconPhysicsContainerView?
        private var animator: UIDynamicAnimator?
        private let gravityBehavior = UIGravityBehavior()
        private let collisionBehavior = UICollisionBehavior()
        private let itemBehavior = UIDynamicItemBehavior()
        private let motionManager = CMMotionManager()
        private var tilesByID: [String: AppIconPhysicsTileView] = [:]
        private var orderedIDs: [String] = []
        private var didPlaceInitialDrop = false
        private var lastContainerBoundsSize: CGSize = .zero
        private var lastCollisionSoundTime: CFTimeInterval = 0
        private var initialDropStartTime: CFTimeInterval = 0
        private var entranceDropActivationToken: Int = 0
        private var hasActivatedEntranceDrop = false
        private let collisionVelocityThreshold: CGFloat = 140
        private let collisionSoundCooldown: CFTimeInterval = 0.14
        private let settledGravityMagnitude: CGFloat = 1.25
        private let defaultDropGravity = CGVector(dx: 0, dy: 1)
        private let minimumEntranceGravityY: CGFloat = 0.68
        private let maximumEntranceGravityX: CGFloat = 0.08
        private let entranceAssistDuration: CFTimeInterval = 0.55
        private let entranceActivationDelay: CFTimeInterval = 0.18
        private let initialDropVelocity: CGFloat = 210
        private var filteredGravity: CGVector
        private let gravitySmoothing: CGFloat = 0.16

        init(parent: AppIconPhysicsPicker) {
            self.parent = parent
            self.filteredGravity = defaultDropGravity
        }

        func attach(to container: AppIconPhysicsContainerView) {
            self.container = container
            container.coordinator = self
            container.clipsToBounds = true
            container.backgroundColor = .clear
            applyCurrentState(animated: false)
            kickstartInitialDropIfNeeded()
            startMotionUpdatesIfNeeded()
            FeedbackService.prepareInteractive()
        }

        func applyCurrentState(animated: Bool) {
            guard let container else { return }
            ensureAnimatorAndTileState(in: container)
            restartEntranceIfNeeded(clampActiveTiles: animated)
        }

        func containerDidLayout() {
            guard let container else { return }
            let bounds = container.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            ensureAnimatorAndTileState(in: container)

            let sizeChanged = bounds.size != lastContainerBoundsSize
            lastContainerBoundsSize = bounds.size
            updateCollisionBounds(in: container)
            restartEntranceIfNeeded(clampActiveTiles: sizeChanged)
        }

        func stopMotionUpdates() {
            entranceDropActivationToken += 1
            hasActivatedEntranceDrop = false
            motionManager.stopDeviceMotionUpdates()
        }

        func kickstartInitialDropIfNeeded() {
            guard let container else { return }
            let bounds = container.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            if animator == nil {
                setupAnimatorIfNeeded(referenceView: container)
            }

            ensureAnimatorAndTileState(in: container)

            guard needsEntranceGravityAssist() else { return }

            filteredGravity = defaultDropGravity
            gravityBehavior.gravityDirection = filteredGravity
            didPlaceInitialDrop = placeTilesAtTop()
        }

        private func ensureAnimatorAndTileState(in container: AppIconPhysicsContainerView) {
            if animator == nil, container.bounds.width > 0, container.bounds.height > 0 {
                setupAnimatorIfNeeded(referenceView: container)
            }
            syncTiles(in: container)
            updateTileStates()
        }

        private func restartEntranceIfNeeded(clampActiveTiles: Bool) {
            if !didPlaceInitialDrop || !hasActivatedEntranceDrop {
                didPlaceInitialDrop = placeTilesAtTop()
            } else if clampActiveTiles {
                keepTilesInsideBounds()
            }
        }

        private func setupAnimatorIfNeeded(referenceView: UIView) {
            guard animator == nil else { return }
            let animator = UIDynamicAnimator(referenceView: referenceView)

            gravityBehavior.magnitude = 0
            gravityBehavior.gravityDirection = filteredGravity
            collisionBehavior.collisionDelegate = self
            updateCollisionBounds(in: referenceView)

            itemBehavior.elasticity = 0.83
            itemBehavior.friction = 0.06
            itemBehavior.resistance = 0.08
            itemBehavior.angularResistance = 0.18
            itemBehavior.allowsRotation = true
            itemBehavior.density = 0.78

            animator.addBehavior(gravityBehavior)
            animator.addBehavior(collisionBehavior)
            animator.addBehavior(itemBehavior)
            self.animator = animator
        }

        private func syncTiles(in container: UIView) {
            let newOrderedIDs = parent.icons.map(\.id)
            let newIDSet = Set(newOrderedIDs)

            for (id, tile) in tilesByID where !newIDSet.contains(id) {
                gravityBehavior.removeItem(tile)
                collisionBehavior.removeItem(tile)
                itemBehavior.removeItem(tile)
                tile.removeFromSuperview()
                tilesByID.removeValue(forKey: id)
            }

            for (index, icon) in parent.icons.enumerated() {
                if let tile = tilesByID[icon.id] {
                    tile.updateIcon(icon)
                    continue
                }

                let tile = AppIconPhysicsTileView(icon: icon, tileSize: parent.layout.tileSize)
                if canPlaceInitialGrid(in: container.bounds) {
                    tile.center = initialDropCenter(
                        for: index,
                        in: container.bounds,
                        totalCount: newOrderedIDs.count
                    )
                }
                tile.addTarget(self, action: #selector(handleTileTap(_:)), for: .touchUpInside)
                container.addSubview(tile)
                tilesByID[icon.id] = tile
                gravityBehavior.addItem(tile)
                collisionBehavior.addItem(tile)
                itemBehavior.addItem(tile)
            }

            orderedIDs = newOrderedIDs
        }

        private func updateTileStates() {
            for icon in parent.icons {
                guard let tile = tilesByID[icon.id] else { continue }
                let isSelected = parent.currentIconID == icon.id
                let isMemberIcon = !AppIconManager.AppIcon.freeIconIDs.contains(icon.id)
                let isLocked = isMemberIcon && !parent.memberUnlocked
                let isDisabled = parent.isApplying || (!isLocked && isSelected)

                tile.applyState(
                    isSelected: isSelected,
                    isLocked: isLocked,
                    isDarkMode: parent.isDarkMode,
                    isDisabled: isDisabled
                )
                tile.isUserInteractionEnabled = !isDisabled
            }
        }

        @discardableResult
        private func placeTilesAtTop() -> Bool {
            guard let container else { return false }
            guard canPlaceInitialGrid(in: container.bounds) else { return false }

            let width = container.bounds.width
            let height = container.bounds.height
            guard width > 0, height > 0 else { return false }

            entranceDropActivationToken += 1
            let activationToken = entranceDropActivationToken
            hasActivatedEntranceDrop = false
            gravityBehavior.magnitude = 0
            filteredGravity = defaultDropGravity
            gravityBehavior.gravityDirection = filteredGravity

            for (index, id) in orderedIDs.enumerated() {
                guard let tile = tilesByID[id] else { continue }
                tile.center = initialDropCenter(
                    for: index,
                    in: container.bounds,
                    totalCount: orderedIDs.count
                )

                let linearVelocity = itemBehavior.linearVelocity(for: tile)
                itemBehavior.addLinearVelocity(
                    CGPoint(x: -linearVelocity.x, y: -linearVelocity.y),
                    for: tile
                )
                let angularVelocity = itemBehavior.angularVelocity(for: tile)
                itemBehavior.addAngularVelocity(-angularVelocity, for: tile)

                animator?.updateItem(usingCurrentState: tile)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + entranceActivationDelay) { [weak self] in
                guard let self else { return }
                guard self.entranceDropActivationToken == activationToken else { return }

                self.hasActivatedEntranceDrop = true
                self.initialDropStartTime = CFAbsoluteTimeGetCurrent()
                self.filteredGravity = self.defaultDropGravity
                self.gravityBehavior.gravityDirection = self.filteredGravity
                self.gravityBehavior.magnitude = self.settledGravityMagnitude

                for id in self.orderedIDs {
                    guard let tile = self.tilesByID[id] else { continue }
                    self.itemBehavior.addLinearVelocity(
                        CGPoint(x: 0, y: self.initialDropVelocity),
                        for: tile
                    )
                    self.animator?.updateItem(usingCurrentState: tile)
                }
            }

            return true
        }

        private func canPlaceInitialGrid(in bounds: CGRect) -> Bool {
            let minimumWidth = parent.layout.tileSize * 3 + parent.layout.initialDropSpacing * 2 + parent.layout.contentInset
            let minimumHeight = parent.layout.tileSize * 3 + parent.layout.initialDropSpacing * 2
            return bounds.width >= minimumWidth && bounds.height >= minimumHeight
        }

        private func initialDropCenter(for index: Int, in bounds: CGRect, totalCount: Int) -> CGPoint {
            let tileSize = parent.layout.tileSize
            let halfSize = tileSize / 2
            let columns = min(3, max(totalCount, 1))
            let preferredSpacing = parent.layout.initialDropSpacing
            let availableRowWidth = bounds.width - parent.layout.contentInset
            let maximumSpacing: CGFloat

            if columns > 1 {
                maximumSpacing = max(
                    (availableRowWidth - CGFloat(columns) * tileSize) / CGFloat(columns - 1),
                    0
                )
            } else {
                maximumSpacing = 0
            }

            let spacing = min(preferredSpacing, maximumSpacing)
            let col = index % columns
            let row = index / columns
            let itemsInRow = min(totalCount - row * columns, columns)
            let rowWidth = CGFloat(itemsInRow) * tileSize + CGFloat(max(itemsInRow - 1, 0)) * spacing
            let startX = (bounds.width - rowWidth) / 2 + halfSize
            let x = startX + CGFloat(col) * (tileSize + spacing)
            let y = halfSize + parent.layout.initialDropTopInset + CGFloat(row) * (tileSize + spacing)

            return CGPoint(x: x, y: y)
        }

        private func updateCollisionBounds(in container: UIView) {
            collisionBehavior.setTranslatesReferenceBoundsIntoBoundary(
                with: .zero
            )
        }

        private func needsEntranceGravityAssist() -> Bool {
            guard !orderedIDs.isEmpty else { return false }
            return orderedIDs.allSatisfy { id in
                guard let tile = tilesByID[id] else { return true }
                return tile.frame.maxY <= 0
            }
        }

        private func shouldApplyEntranceGravityAssist() -> Bool {
            if !hasActivatedEntranceDrop {
                return true
            }
            if needsEntranceGravityAssist() {
                return true
            }
            return CFAbsoluteTimeGetCurrent() - initialDropStartTime < entranceAssistDuration
        }

        private func keepTilesInsideBounds() {
            guard let container else { return }
            let bounds = container.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            let halfSize = parent.layout.tileSize / 2
            for id in orderedIDs {
                guard let tile = tilesByID[id] else { continue }
                var center = tile.center
                center.x = min(max(center.x, halfSize), bounds.width - halfSize)
                center.y = min(max(center.y, halfSize), bounds.height - halfSize)
                if center != tile.center {
                    tile.center = center
                    animator?.updateItem(usingCurrentState: tile)
                }
            }
        }

        private func startMotionUpdatesIfNeeded() {
            guard motionManager.isDeviceMotionAvailable else { return }
            guard !motionManager.isDeviceMotionActive else { return }

            motionManager.deviceMotionUpdateInterval = 1.0 / 45.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                self.updateGravity(with: motion.gravity)
            }
        }

        private func updateGravity(with gravity: CMAcceleration) {
            var dx = gravity.x
            var dy = -gravity.y

            if let orientation = container?.window?.windowScene?.effectiveGeometry.interfaceOrientation {
                switch orientation {
                case .portrait:
                    dx = gravity.x
                    dy = -gravity.y
                case .portraitUpsideDown:
                    dx = -gravity.x
                    dy = gravity.y
                case .landscapeLeft:
                    dx = gravity.y
                    dy = gravity.x
                case .landscapeRight:
                    dx = -gravity.y
                    dy = -gravity.x
                default:
                    break
                }
            }

            let a = gravitySmoothing
            filteredGravity.dx += a * (CGFloat(dx) - filteredGravity.dx)
            filteredGravity.dy += a * (CGFloat(dy) - filteredGravity.dy)

            if shouldApplyEntranceGravityAssist() {
                filteredGravity.dx = max(min(filteredGravity.dx, maximumEntranceGravityX), -maximumEntranceGravityX)
                filteredGravity.dy = max(filteredGravity.dy, minimumEntranceGravityY)
            }

            gravityBehavior.gravityDirection = filteredGravity
        }

        @objc
        private func handleTileTap(_ sender: AppIconPhysicsTileView) {
            parent.onTapIcon(sender.icon)
        }

        func collisionBehavior(
            _ behavior: UICollisionBehavior,
            beganContactFor item1: UIDynamicItem,
            with item2: UIDynamicItem,
            at p: CGPoint
        ) {
            emitCollisionSoundIfNeeded(item1: item1, item2: item2)
        }

        func collisionBehavior(
            _ behavior: UICollisionBehavior,
            beganContactFor item: UIDynamicItem,
            withBoundaryIdentifier identifier: NSCopying?,
            at p: CGPoint
        ) {
            emitCollisionSoundIfNeeded(item1: item, item2: nil)
        }

        private func emitCollisionSoundIfNeeded(item1: UIDynamicItem, item2: UIDynamicItem?) {
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastCollisionSoundTime >= collisionSoundCooldown else { return }

            let v1 = itemBehavior.linearVelocity(for: item1)
            let velocityMagnitude: CGFloat
            if let item2 {
                let v2 = itemBehavior.linearVelocity(for: item2)
                velocityMagnitude = hypot(v1.x - v2.x, v1.y - v2.y)
            } else {
                velocityMagnitude = hypot(v1.x, v1.y)
            }

            guard velocityMagnitude >= collisionVelocityThreshold else { return }

            lastCollisionSoundTime = now
            FeedbackService.gearTick()
        }
    }
}

private final class AppIconPhysicsContainerView: UIView {
    weak var coordinator: AppIconPhysicsPicker.Coordinator?

    private func requestStableLayoutPass() {
        setNeedsLayout()
        superview?.setNeedsLayout()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutIfNeeded()
            self.superview?.layoutIfNeeded()
            self.coordinator?.containerDidLayout()
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            coordinator?.stopMotionUpdates()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            requestStableLayoutPass()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.requestStableLayoutPass()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        coordinator?.containerDidLayout()
    }
}

private final class AppIconPhysicsTileView: UIControl {
    private(set) var icon: AppIconManager.AppIcon
    private let imageView = UIImageView()
    private let lockBadgeView = UIView()
    private let lockImageView = UIImageView()
    private let cornerRadius: CGFloat = 20

    init(icon: AppIconManager.AppIcon, tileSize: CGFloat) {
        self.icon = icon
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: tileSize, height: tileSize)))

        imageView.image = UIImage(named: icon.previewAssetName)
        imageView.contentMode = .scaleAspectFill
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.layer.cornerRadius = cornerRadius
        imageView.layer.masksToBounds = true
        addSubview(imageView)

        layer.cornerRadius = cornerRadius
        layer.borderWidth = 1
        layer.masksToBounds = true

        lockImageView.image = UIImage(systemName: "lock.fill")
        lockImageView.contentMode = .scaleAspectFit
        lockBadgeView.addSubview(lockImageView)
        addSubview(lockBadgeView)

        isExclusiveTouch = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let badgeSize: CGFloat = 22
        let inset: CGFloat = 6
        lockBadgeView.frame = CGRect(
            x: bounds.width - badgeSize - inset,
            y: inset,
            width: badgeSize,
            height: badgeSize
        )
        lockBadgeView.layer.cornerRadius = badgeSize / 2
        lockImageView.frame = lockBadgeView.bounds.insetBy(dx: 5, dy: 5)
    }

    func updateIcon(_ icon: AppIconManager.AppIcon) {
        guard self.icon.id != icon.id || self.icon.previewAssetName != icon.previewAssetName else { return }
        self.icon = icon
        imageView.image = UIImage(named: icon.previewAssetName)
    }

    func applyState(isSelected: Bool, isLocked: Bool, isDarkMode: Bool, isDisabled: Bool) {
        if isSelected {
            layer.borderColor = (isDarkMode ? UIColor.white.withAlphaComponent(0.60) : UIColor.black.withAlphaComponent(0.35)).cgColor
            layer.borderWidth = 1.5
        } else {
            layer.borderColor = (isDarkMode ? UIColor.white.withAlphaComponent(0.16) : UIColor.black.withAlphaComponent(0.10)).cgColor
            layer.borderWidth = 1.0
        }

        alpha = (isDisabled && !isSelected) ? 0.6 : 1.0
        lockBadgeView.isHidden = !isLocked
        lockBadgeView.backgroundColor = isDarkMode ? UIColor.black.withAlphaComponent(0.68) : UIColor.white.withAlphaComponent(0.90)
        lockImageView.tintColor = isDarkMode ? UIColor.white.withAlphaComponent(0.92) : UIColor.black.withAlphaComponent(0.86)
    }
}
#endif

private struct FAQItem: Identifiable {
    let id: String
    let question: String
    let answer: String
}

private struct FAQSheetView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let items: [FAQItem]
    @State private var expandedItemIDs: Set<String> = []

    private var isDarkMode: Bool { colorScheme == .dark }
    private var backgroundGradient: LinearGradient {
        AppColors.appBackgroundGradient(themeMode: appState.themeMode, isDarkMode: isDarkMode)
    }
    private var heroTitleColor: Color {
        AppColors.primaryText(isDarkMode: isDarkMode)
    }
    private var heroBodyColor: Color {
        isDarkMode ? AppColors.nocturneTextSecondary : Color.black.opacity(0.52)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ThemedBackgroundView(
                themeMode: appState.themeMode,
                isDarkMode: isDarkMode
            )

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Spacer().frame(height: 28)

                    FAQHeroCard(
                        eyebrow: appState.localized("Learning FAQ", "学习机制 FAQ", "Learning FAQ"),
                        title: appState.localized(
                            "Understand how Explore cards are selected, repeated, and truly completed.",
                            "了解首页卡片是如何被选中、回流，以及何时才算真正完成。",
                            "Understand how Explore cards are selected, repeated, and truly completed."
                        ),
                        titleColor: heroTitleColor,
                        bodyColor: heroBodyColor
                    )

                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            FAQAccordionCard(
                                item: item,
                                isExpanded: expandedItemIDs.contains(item.id),
                                onToggle: { toggle(item.id) }
                            )
                        }
                    }

                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 20)
            }

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.82) : Color.black.opacity(0.56))
                    .shadow(color: Color.black.opacity(isDarkMode ? 0.24 : 0.10), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
        .onAppear {
            if expandedItemIDs.isEmpty, let firstID = items.first?.id {
                expandedItemIDs.insert(firstID)
            }
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            if expandedItemIDs.contains(id) {
                expandedItemIDs.remove(id)
            } else {
                expandedItemIDs.insert(id)
            }
        }
    }
}

private struct FAQHeroCard: View {
    let eyebrow: String
    let title: String
    let titleColor: Color
    let bodyColor: Color
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }
    private var borderColor: Color {
        AppColors.elevatedSurfaceBorder(themeMode: appState.themeMode, isDarkMode: isDarkMode)
    }
    private var fillColor: Color {
        if AppColors.usesPorcelainStyle(themeMode: appState.themeMode, isDarkMode: isDarkMode) {
            return AppColors.porcelainCard
        }
        return isDarkMode ? AppColors.nocturneSurface.opacity(0.72) : Color.white.opacity(0.82)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .themedGlassSurface(themeMode: appState.themeMode, isDarkMode: isDarkMode, elevated: true)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.nocturneWarmGlow.opacity(isDarkMode ? 0.14 : 0.18),
                            AppColors.nocturneCoolGlow.opacity(isDarkMode ? 0.06 : 0.09),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AppColors.nocturneWarmGlow.opacity(isDarkMode ? 0.18 : 0.16))
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isDarkMode ? AppColors.nocturneCoolGlow : Color(red: 0.02, green: 0.48, blue: 1.00))
                    }
                    .frame(width: 34, height: 34)

                    Text(eyebrow)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(bodyColor)
                }

                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(22)
        }
    }
}

private struct FAQAccordionCard: View {
    let item: FAQItem
    let isExpanded: Bool
    let onToggle: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }
    private var questionColor: Color {
        isDarkMode ? AppColors.nocturneTextPrimary : Color.black.opacity(0.84)
    }
    private var answerColor: Color {
        isDarkMode ? AppColors.nocturneTextSecondary : Color.black.opacity(0.56)
    }
    private var borderColor: Color {
        if AppColors.usesPorcelainStyle(themeMode: appState.themeMode, isDarkMode: isDarkMode) {
            return Color.black.opacity(0.08)
        }
        return isDarkMode ? AppColors.nocturneBorder : Color.white.opacity(0.68)
    }
    private var dividerColor: Color {
        isDarkMode ? AppColors.nocturneBorderSoft : Color.black.opacity(0.08)
    }
    private var fillColor: Color {
        if AppColors.usesPorcelainStyle(themeMode: appState.themeMode, isDarkMode: isDarkMode) {
            return AppColors.porcelainCard
        }
        return isDarkMode ? AppColors.nocturneSurface.opacity(0.74) : Color.white.opacity(0.84)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 14) {
                    Text(item.question)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(questionColor)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(answerColor)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)
                    .padding(.horizontal, 18)

                Text(item.answer)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(answerColor)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .themedGlassSurface(themeMode: appState.themeMode, isDarkMode: isDarkMode, elevated: true)
        )
    }
}

private struct LegalDocumentSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let themeMode: ThemeMode
    let title: String
    let subtitle: String
    let paragraphs: [String]

    private var isDarkMode: Bool { colorScheme == .dark }
    private var backgroundGradient: LinearGradient {
        AppColors.appBackgroundGradient(themeMode: themeMode, isDarkMode: isDarkMode)
    }
    private var titleColor: Color {
        AppColors.primaryText(isDarkMode: isDarkMode)
    }
    private var subtitleColor: Color {
        isDarkMode ? AppColors.nocturneTextSecondary : Color.black.opacity(0.54)
    }
    private var bodyColor: Color {
        isDarkMode ? Color.white.opacity(0.74) : Color.black.opacity(0.70)
    }
    private var borderColor: Color {
        AppColors.elevatedSurfaceBorder(themeMode: themeMode, isDarkMode: isDarkMode)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ThemedBackgroundView(
                themeMode: themeMode,
                isDarkMode: isDarkMode
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Spacer().frame(height: 28)

                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(titleColor)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .lineSpacing(5)
                                .foregroundStyle(bodyColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .themedGlassSurface(themeMode: themeMode, isDarkMode: isDarkMode, elevated: true)
                    )

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
            }

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.82) : Color.black.opacity(0.56))
                    .shadow(color: Color.black.opacity(isDarkMode ? 0.24 : 0.10), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
    }
}

private struct PillSelector: View {
    enum VisualStyle {
        case standard
        case glossy
    }

    let labels: [String]
    let symbols: [String]?
    let selectedIndex: Int
    let verticalPadding: CGFloat
    let style: VisualStyle
    let onSelect: (Int) -> Void
    private let controlHeight: CGFloat
    private let glossyIndicatorVInset: CGFloat?
    private let glossyIndicatorHInset: CGFloat?

    @Environment(\.colorScheme) private var colorScheme

    init(
        labels: [String],
        symbols: [String]? = nil,
        selectedIndex: Int,
        verticalPadding: CGFloat = 9,
        controlHeight: CGFloat = 52,
        glossyIndicatorVerticalInset: CGFloat? = nil,
        glossyIndicatorHorizontalInset: CGFloat? = nil,
        style: VisualStyle = .standard,
        onSelect: @escaping (Int) -> Void
    ) {
        self.labels = labels
        self.symbols = symbols
        self.selectedIndex = selectedIndex
        self.verticalPadding = verticalPadding
        self.controlHeight = controlHeight
        self.glossyIndicatorVInset = glossyIndicatorVerticalInset
        self.glossyIndicatorHInset = glossyIndicatorHorizontalInset
        self.style = style
        self.onSelect = onSelect
    }

    private var clampedSelectedIndex: Int {
        guard !labels.isEmpty else { return 0 }
        return min(max(selectedIndex, 0), labels.count - 1)
    }

    private var selectedForeground: Color {
        switch style {
        case .glossy:
            return colorScheme == .dark
                ? Color.white.opacity(0.92)
                : Color.black.opacity(0.82)
        case .standard:
            return colorScheme == .dark
                ? Color(red: 0.42, green: 0.86, blue: 0.36)
                : Color(red: 0.04, green: 0.40, blue: 0.12)
        }
    }

    private var unselectedForeground: Color {
        switch style {
        case .glossy:
            return colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.40)
        case .standard:
            return colorScheme == .dark ? Color.white.opacity(0.52) : Color.black.opacity(0.42)
        }
    }

    private var trackBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.60)
    }

    private var indicatorBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.90)
    }

    @ViewBuilder
    private func segmentLabel(at idx: Int) -> some View {
        if let symbols, symbols.indices.contains(idx) {
            Image(systemName: symbols[idx])
                .font(.system(size: 13, weight: .semibold))
                .symbolEffect(.bounce, options: .nonRepeating, value: clampedSelectedIndex == idx)
        } else {
            Text(labels[idx])
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
    }

    private func glossySelectedIndicator() -> some View {
        let edgeGradient = LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.38 : 0.75),
                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.28)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        return Capsule()
            .fill(.regularMaterial)
            .overlay(
                Capsule()
                    .stroke(edgeGradient, lineWidth: 1)
            )
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06), lineWidth: 0.5)
                    .padding(-0.4)
            )
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.10 : 0.35),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.45)
                        )
                    )
                    .padding(2)
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.40 : 0.12), radius: 4, x: 0, y: 2)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.06), radius: 1.5, x: 0, y: 0.5)
    }

    private var indicatorHorizontalInset: CGFloat {
        if style == .glossy, let h = glossyIndicatorHInset {
            return h
        }
        switch style {
        case .glossy:
            return colorScheme == .dark ? 3.5 : 4
        case .standard:
            return 4
        }
    }

    private var indicatorVerticalInset: CGFloat {
        if style == .glossy, let v = glossyIndicatorVInset {
            return v
        }
        switch style {
        case .glossy:
            return colorScheme == .dark ? 3.5 : 3
        case .standard:
            return 3
        }
    }

    @ViewBuilder
    private func slidingIndicator(width: CGFloat, height: CGFloat) -> some View {
        Group {
            switch style {
            case .glossy:
                glossySelectedIndicator()
            case .standard:
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(
                        Capsule()
                            .stroke(indicatorBorderColor, lineWidth: 0.8)
                    )
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.12),
                        radius: 4, x: 0, y: 2
                    )
            }
        }
        .frame(width: width, height: height)
        .compositingGroup()
    }

    var body: some View {
        GeometryReader { geo in
            let count = max(labels.count, 1)
            let segW = geo.size.width / CGFloat(count)
            let hInset = indicatorHorizontalInset
            let vInset = indicatorVerticalInset
            let indW = max(0, segW - hInset * 2)
            let indH = max(0, geo.size.height - vInset * 2)
            ZStack(alignment: .topLeading) {
                slidingIndicator(width: indW, height: indH)
                    .offset(
                        x: CGFloat(clampedSelectedIndex) * segW + hInset,
                        y: vInset
                    )
                HStack(spacing: 0) {
                    ForEach(labels.indices, id: \.self) { idx in
                        segmentLabel(at: idx)
                            .foregroundStyle(idx == clampedSelectedIndex ? selectedForeground : unselectedForeground)
                            .padding(.vertical, verticalPadding)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(idx) }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .padding(4)
        .background(
            Group {
                switch style {
                case .glossy:
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(
                                    Color.white.opacity(colorScheme == .dark ? 0.14 : 0.45),
                                    lineWidth: 0.75
                                )
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.05), lineWidth: 0.5)
                                .padding(-0.35)
                        )
                        .shadow(
                            color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.07),
                            radius: 3, x: 0, y: 1.5
                        )
                case .standard:
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(trackBorderColor, lineWidth: 0.8)
                        )
                }
            }
        )
        .animation(.spring(response: 0.2, dampingFraction: 0.92), value: clampedSelectedIndex)
        .animation(.easeInOut(duration: 0.30), value: colorScheme)
        .sensoryFeedback(.selection, trigger: clampedSelectedIndex)
        .frame(maxWidth: .infinity, minHeight: controlHeight, maxHeight: controlHeight)
        .padding(.horizontal, 7)
    }
}

private struct SettingsGroupCard<Content: View>: View {
    let content: Content
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var borderColor: Color {
        if AppColors.usesPorcelainStyle(themeMode: appState.themeMode, isDarkMode: colorScheme == .dark) {
            return Color.black.opacity(0.08)
        }
        return colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.07)
    }

    private var fillColor: Color {
        if AppColors.usesPorcelainStyle(themeMode: appState.themeMode, isDarkMode: colorScheme == .dark) {
            return AppColors.porcelainCard
        }
        return colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.95)
    }

    private var cardShadowColor: Color {
        if AppColors.usesPorcelainStyle(themeMode: appState.themeMode, isDarkMode: colorScheme == .dark) {
            return Color.black.opacity(0.06)
        }
        return colorScheme == .dark ? Color.clear : Color.black.opacity(0.04)
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .themedGlassSurface(themeMode: appState.themeMode, isDarkMode: colorScheme == .dark, elevated: true)
        )
        .shadow(color: cardShadowColor, radius: 3, x: 0, y: 1)
    }
}

private struct SettingsCardRow<Trailing: View>: View {
    let icon: String
    let iconAssetName: String?
    let title: String
    let titleTrailingSymbol: String?
    let subtitle: String
    let titleFontSize: CGFloat
    let rowVerticalPadding: CGFloat
    let contentMinHeight: CGFloat
    let showsSubtitle: Bool
    let showsDivider: Bool
    let matchPickerFont: Bool
    let trailing: Trailing
    @Environment(\.colorScheme) private var colorScheme

    init(
        icon: String,
        iconAssetName: String? = nil,
        title: String,
        titleTrailingSymbol: String? = nil,
        subtitle: String,
        titleFontSize: CGFloat = 13,
        rowVerticalPadding: CGFloat = 16,
        contentMinHeight: CGFloat = 34,
        showsSubtitle: Bool = false,
        showsDivider: Bool,
        matchPickerFont: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.iconAssetName = iconAssetName
        self.title = title
        self.titleTrailingSymbol = titleTrailingSymbol
        self.subtitle = subtitle
        self.titleFontSize = titleFontSize
        self.rowVerticalPadding = rowVerticalPadding
        self.contentMinHeight = contentMinHeight
        self.showsSubtitle = showsSubtitle
        self.showsDivider = showsDivider
        self.matchPickerFont = matchPickerFont
        self.trailing = trailing()
    }

    private var resolvedTitleFont: Font {
        .system(size: 16, weight: .semibold, design: .rounded)
    }

    private var resolvedSubtitleFont: Font {
        .system(size: 14, weight: .regular, design: .rounded)
    }

    private var isDarkMode: Bool { colorScheme == .dark }
    private var iconColor: Color {
        isDarkMode ? Color.white.opacity(0.54) : Color.black.opacity(0.42)
    }
    private var customIconColor: Color {
        isDarkMode ? Color.white.opacity(0.86) : Color.black.opacity(0.76)
    }
    private var titleColor: Color {
        isDarkMode ? Color.white.opacity(0.88) : Color.black.opacity(0.84)
    }
    private var subtitleColor: Color {
        isDarkMode ? Color.white.opacity(0.52) : Color.black.opacity(0.44)
    }
    private var dividerColor: Color {
        isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let iconAssetName, let customIcon = loadCustomIcon(named: iconAssetName) {
                    customIcon
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .regular))
                }
            }
            .foregroundStyle(iconAssetName == nil ? iconColor : customIconColor)
            .frame(width: 26, alignment: .center)

            if showsSubtitle {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(resolvedTitleFont)
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)

                        if let titleTrailingSymbol {
                            Image(systemName: titleTrailingSymbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(subtitleColor)
                        }
                    }
                    Text(subtitle)
                        .font(resolvedSubtitleFont)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                }
            } else {
                HStack(spacing: 6) {
                    Text(title)
                        .font(resolvedTitleFont)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)

                    if let titleTrailingSymbol {
                        Image(systemName: titleTrailingSymbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(subtitleColor)
                    }
                }
            }

            Spacer(minLength: 10)

            trailing
        }
        .frame(minHeight: contentMinHeight, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)
                    .padding(.leading, 70)
                    .padding(.trailing, 14)
            }
        }
    }

    private func loadCustomIcon(named name: String) -> Image? {
        #if os(iOS)
        #if SWIFT_PACKAGE
        if let uiImage = UIImage(named: name, in: .module, compatibleWith: nil) {
            return Image(uiImage: uiImage)
        }
        #else
        if let uiImage = UIImage(named: name) {
            return Image(uiImage: uiImage)
        }
        #endif
        #elseif os(macOS)
        #if SWIFT_PACKAGE
        if let nsImage = Bundle.module.image(forResource: name) {
            return Image(nsImage: nsImage)
        }
        #else
        if let nsImage = NSImage(named: name) {
            return Image(nsImage: nsImage)
        }
        #endif
        #endif
        return nil
    }
}

private struct NotificationReminderSettingsCard: View {
    let title: String
    let displayTime: String
    let stepIndex: Int
    @Binding var isEnabled: Bool
    let onChangeStep: (Int) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isKnobDragging = false
    @State private var knobDragBiasX: CGFloat = 0
    @State private var lastAudibleStepIndex: Int?

    private var isDarkMode: Bool { colorScheme == .dark }
    private var titleColor: Color {
        isDarkMode ? Color.white.opacity(0.88) : Color.black.opacity(0.84)
    }
    private var iconColor: Color {
        isDarkMode ? Color.white.opacity(0.54) : Color.black.opacity(0.42)
    }
    private var curveColor: Color {
        isDarkMode ? Color.white.opacity(0.78) : Color.black.opacity(0.52)
    }
    private var maxStepIndex: Int { 95 }
    private var noonStepIndex: Int { 48 }

    private func progress(for stepIndex: Int) -> CGFloat {
        let clamped = min(max(stepIndex, 0), maxStepIndex)
        if clamped <= noonStepIndex {
            return CGFloat(clamped) / CGFloat(noonStepIndex * 2)
        }
        let rightStepCount = max(maxStepIndex - noonStepIndex, 1)
        return 0.5 + CGFloat(clamped - noonStepIndex) / CGFloat(rightStepCount * 2)
    }

    private func stepIndex(for progress: CGFloat) -> Int {
        let clamped = min(max(progress, 0), 1)
        if clamped <= 0.5 {
            let left = Int((clamped * CGFloat(noonStepIndex * 2)).rounded())
            return min(max(left, 0), noonStepIndex)
        }
        let rightStepCount = max(maxStepIndex - noonStepIndex, 1)
        let right = Int((CGFloat(noonStepIndex) + (clamped - 0.5) * CGFloat(rightStepCount * 2)).rounded())
        return min(max(right, noonStepIndex), maxStepIndex)
    }

    private func snappedStepIndex(for locationX: CGFloat, width: CGFloat) -> Int {
        let minX = NotificationReminderCurveShape.horizontalInset
        let maxX = max(minX, width - NotificationReminderCurveShape.horizontalInset)
        let clampedX = min(max(locationX, minX), maxX)
        let progress = (clampedX - minX) / max(maxX - minX, 1)
        return stepIndex(for: progress)
    }

    private func applyDragStep(at locationX: CGFloat, width: CGFloat, playSound: Bool) {
        let snapped = snappedStepIndex(for: locationX, width: width)
        if playSound, let lastAudibleStepIndex, snapped != lastAudibleStepIndex {
            FeedbackService.dropletTick(steps: abs(snapped - lastAudibleStepIndex))
        }
        lastAudibleStepIndex = snapped
        onChangeStep(snapped)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(iconColor)
                    .frame(width: 26, alignment: .center)

                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)

                Spacer(minLength: 0)

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    .scaleEffect(0.84)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            VStack(spacing: 8) {
                GeometryReader { geo in
                    let progress = progress(for: stepIndex)
                    let curveRect = geo.frame(in: .local).insetBy(
                        dx: NotificationReminderCurveShape.horizontalInset,
                        dy: NotificationReminderCurveShape.verticalInset
                    )
                    let markerPoint = NotificationReminderCurveShape.point(in: curveRect, progress: progress)

                    ZStack {
                        NotificationReminderCurveShape()
                            .stroke(
                                curveColor.opacity(isEnabled ? 0.96 : 0.46),
                                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                            )

                        NotificationLiquidGlassKnob(
                            isDarkMode: isDarkMode,
                            isEnabled: isEnabled,
                            isDragging: isKnobDragging,
                            dragBiasX: knobDragBiasX
                        )
                            .frame(width: 25, height: 25)
                            .position(x: markerPoint.x, y: markerPoint.y)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isKnobDragging = true
                                knobDragBiasX = min(max(value.translation.width / 34, -1), 1)
                                applyDragStep(at: value.location.x, width: geo.size.width, playSound: true)
                            }
                            .onEnded { value in
                                isKnobDragging = false
                                knobDragBiasX = 0
                                applyDragStep(at: value.location.x, width: geo.size.width, playSound: true)
                            }
                    )
                }
                .frame(height: 42)
            .padding(.horizontal, 2)
                .padding(.top, 6)

                Text(displayTime)
                    .font(.system(size: 24, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(titleColor.opacity(isEnabled ? 0.94 : 0.60))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 10)
            }
            .padding(.top, 6)
        }
        .onAppear {
            FeedbackService.prepareInteractive()
            lastAudibleStepIndex = stepIndex
        }
        .onChange(of: stepIndex) { _, newValue in
            if !isKnobDragging {
                lastAudibleStepIndex = newValue
            }
        }
    }
}

private struct NotificationLiquidGlassKnob: View {
    let isDarkMode: Bool
    let isEnabled: Bool
    let isDragging: Bool
    let dragBiasX: CGFloat

    private var stretch: CGFloat { min(abs(dragBiasX), 1) }
    private var lensShift: CGFloat { dragBiasX * 0.06 }
    private var surfaceOpacity: Double { isDarkMode ? 0.50 : 0.82 }

    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(surfaceOpacity))
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDarkMode ? 0.40 : 0.72),
                            Color.white.opacity(isDarkMode ? 0.14 : 0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)

            Circle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isDarkMode ? 0.24 : 0.46), location: 0.16),
                            .init(color: Color.black.opacity(isDarkMode ? 0.25 : 0.16), location: 0.46),
                            .init(color: Color.white.opacity(isDarkMode ? 0.20 : 0.38), location: 0.80)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .scaleEffect(x: 1.34, y: 0.66)
                .rotationEffect(.degrees(-14 + Double(dragBiasX) * 8))
                .offset(x: dragBiasX * 2.0, y: 0.8)
                .blur(radius: 1.2)
                .blendMode(.overlay)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isDarkMode ? 0.70 : 0.95),
                            Color.white.opacity(0)
                        ],
                        center: UnitPoint(x: 0.30 + lensShift, y: 0.26),
                        startRadius: 0,
                        endRadius: 10.5
                    )
                )
                .blendMode(.screen)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(isDarkMode ? 0.30 : 0.16),
                            Color.black.opacity(0)
                        ],
                        center: UnitPoint(x: 0.72 + lensShift, y: 0.74),
                        startRadius: 0.4,
                        endRadius: 12
                    )
                )
                .blendMode(.multiply)

            Ellipse()
                .stroke(Color.white.opacity(isDarkMode ? 0.58 : 0.90), lineWidth: 1.25)
                .scaleEffect(x: 0.70, y: 0.40)
                .offset(x: dragBiasX * 0.8, y: -4.4)
                .blur(radius: 0.22)
                .blendMode(.screen)

            Ellipse()
                .stroke(Color.black.opacity(isDarkMode ? 0.26 : 0.14), lineWidth: 1.1)
                .scaleEffect(x: 0.78, y: 0.46)
                .offset(x: -dragBiasX * 0.9, y: 4.8)
                .blur(radius: 0.32)
                .blendMode(.multiply)

            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(isDarkMode ? 0.86 : 0.98), location: 0.08),
                            .init(color: Color.white.opacity(isDarkMode ? 0.72 : 0.90), location: 0.34),
                            .init(color: Color.black.opacity(isDarkMode ? 0.40 : 0.24), location: 0.68),
                            .init(color: Color.black.opacity(isDarkMode ? 0.58 : 0.34), location: 0.94)
                        ]),
                        center: .center
                    ),
                    lineWidth: 1.6
                )

            Circle()
                .stroke(Color.white.opacity(isDarkMode ? 0.56 : 0.74), lineWidth: 0.9)
                .scaleEffect(0.90)
                .blur(radius: 0.2)

            Circle()
                .stroke(Color.black.opacity(isDarkMode ? 0.44 : 0.24), lineWidth: 1.9)
                .blur(radius: 1.2)
                .offset(x: 1.2, y: 1.5)
                .mask(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0),
                                    Color.black.opacity(0.95)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        }
        .compositingGroup()
        .opacity(isEnabled ? 1 : 0.74)
        .scaleEffect(
            x: isDragging ? 1.02 + stretch * 0.08 : 1,
            y: isDragging ? 0.98 - stretch * 0.08 : 1
        )
        .offset(x: isDragging ? dragBiasX * 1.8 : 0)
        .shadow(
            color: Color.black.opacity(isDarkMode ? 0.28 : 0.15),
            radius: isDragging ? 9 : 6,
            x: 0,
            y: isDragging ? 3 : 2
        )
        .animation(.spring(response: 0.24, dampingFraction: 0.73), value: isDragging)
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: dragBiasX)
    }
}

private struct NotificationReminderCurveShape: Shape {
    static let horizontalInset: CGFloat = 10
    static let verticalInset: CGFloat = 6
    private static let start = CGPoint(x: 0.08, y: 0.84)
    private static let firstControl = CGPoint(x: 0.23, y: 0.92)
    private static let secondControl = CGPoint(x: 0.38, y: -0.24)
    private static let mid = CGPoint(x: 0.50, y: -0.24)
    private static let thirdControl = CGPoint(x: 0.62, y: -0.24)
    private static let fourthControl = CGPoint(x: 0.77, y: 0.92)
    private static let end = CGPoint(x: 0.92, y: 0.84)

    func path(in rect: CGRect) -> Path {
        let drawRect = rect.insetBy(dx: Self.horizontalInset, dy: Self.verticalInset)
        var path = Path()
        path.move(to: Self.transformed(Self.start, in: drawRect))
        path.addCurve(
            to: Self.transformed(Self.mid, in: drawRect),
            control1: Self.transformed(Self.firstControl, in: drawRect),
            control2: Self.transformed(Self.secondControl, in: drawRect)
        )
        path.addCurve(
            to: Self.transformed(Self.end, in: drawRect),
            control1: Self.transformed(Self.thirdControl, in: drawRect),
            control2: Self.transformed(Self.fourthControl, in: drawRect)
        )
        return path
    }

    static func point(in rect: CGRect, progress: CGFloat) -> CGPoint {
        let clamped = min(max(progress, 0), 1)
        let normalized: CGPoint
        if clamped <= 0.5 {
            normalized = cubicPoint(
                p0: Self.start,
                p1: Self.firstControl,
                p2: Self.secondControl,
                p3: Self.mid,
                t: clamped / 0.5
            )
        } else {
            normalized = cubicPoint(
                p0: Self.mid,
                p1: Self.thirdControl,
                p2: Self.fourthControl,
                p3: Self.end,
                t: (clamped - 0.5) / 0.5
            )
        }
        return transformed(normalized, in: rect)
    }

    private static func transformed(_ normalized: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * normalized.x,
            y: rect.minY + rect.height * normalized.y
        )
    }

    private static func cubicPoint(
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint,
        t: CGFloat
    ) -> CGPoint {
        let u = 1 - t
        let tt = t * t
        let uu = u * u
        let uuu = uu * u
        let ttt = tt * t
        return CGPoint(
            x: (uuu * p0.x) + (3 * uu * t * p1.x) + (3 * u * tt * p2.x) + (ttt * p3.x),
            y: (uuu * p0.y) + (3 * uu * t * p1.y) + (3 * u * tt * p2.y) + (ttt * p3.y)
        )
    }
}

private actor DailyReminderService {
    static let shared = DailyReminderService()

    private let center = UNUserNotificationCenter.current()
    private let requestIdentifier = "croissante.daily.learning.reminder"

    func configure(
        enabled: Bool,
        hour: Int,
        minute: Int,
        title: String,
        body: String
    ) async -> Bool {
        guard enabled else {
            cancel()
            return true
        }

        let status = await notificationAuthorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return await schedule(hour: hour, minute: minute, title: title, body: body)
        case .notDetermined:
            let granted = await requestAuthorization()
            guard granted else { return false }
            return await schedule(hour: hour, minute: minute, title: title, body: body)
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func schedule(hour: Int, minute: Int, title: String, body: String) async -> Bool {
        let clampedHour = min(max(hour, 0), 23)
        let clampedMinute = min(max(minute, 0), 59)

        cancel()

        var dateComponents = DateComponents()
        dateComponents.hour = clampedHour
        dateComponents.minute = clampedMinute

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)

        return await add(request)
    }

    private func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
    }

    private func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async -> Bool {
        await withCheckedContinuation { continuation in
            center.add(request) { error in
                continuation.resume(returning: error == nil)
            }
        }
    }
}

private struct SettingsActionButtonsRow: View {
    let labels: [String]
    let accessibilityLabels: [String]
    let onTap: (Int) -> Void
    @Environment(\.colorScheme) private var colorScheme

    init(labels: [String], accessibilityLabels: [String]? = nil, onTap: @escaping (Int) -> Void) {
        self.labels = labels
        self.accessibilityLabels = accessibilityLabels ?? labels
        self.onTap = onTap
    }

    private var actionColor: Color {
        colorScheme == .dark
            ? Color(red: 0.64, green: 0.64, blue: 0.66)
            : Color(red: 0.52, green: 0.52, blue: 0.54)
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var xIconColor: Color {
        colorScheme == .dark ? .white : .black
    }

    @ViewBuilder
    private func actionLabel(_ label: String, accessibilityLabel: String) -> some View {
        if label == "X" {
            Image("XSocialIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
                .foregroundStyle(xIconColor)
                .accessibilityLabel(accessibilityLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        } else if label.hasPrefix("SF:") {
            let name = String(label.dropFirst(3))
            Image(systemName: name)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(actionColor)
                .accessibilityLabel(accessibilityLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        } else {
            Text(label)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(actionColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
                .padding(.horizontal, 14)

            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                    Button(action: {
                        onTap(idx)
                    }) {
                        actionLabel(label, accessibilityLabel: accessibilityLabels.indices.contains(idx) ? accessibilityLabels[idx] : label)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
        }
    }
}

#if os(iOS)
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

private struct MemberUnlockRow: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var titleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.40)
    }

    private var trackBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .stroke(
                        Color.white.opacity(colorScheme == .dark ? 0.14 : 0.45),
                        lineWidth: 0.75
                    )
            )
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.05), lineWidth: 0.5)
                    .padding(-0.35)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.07),
                radius: 3, x: 0, y: 1.5
            )
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "crown")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(titleColor)
                .frame(width: 22, alignment: .center)
            Text(appState.localized("Member Unlock", "会员解锁", "सदस्य अनलॉक"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(titleColor)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .padding(4)
        .background(trackBackground)
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
        .padding(.horizontal, 7)
        .padding(.horizontal, 20)
    }
}

private struct MemberUnlockPaywallView: View {
    private enum MemberPlan: String, CaseIterable, Identifiable {
        case monthly
        case yearly
        case lifetime

        var id: String { rawValue }

        var storeProduct: StoreKitManager.MemberProduct {
            switch self {
            case .monthly:
                return .monthly
            case .yearly:
                return .yearly
            case .lifetime:
                return .lifetime
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var storeKitManager: StoreKitManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showingAllPlans: Bool
    @State private var selectedPlan: MemberPlan = .monthly
    @State private var storeAlertTitle = ""
    @State private var storeAlertMessage = ""
    @State private var showingStoreAlert = false

    private var benefits: [MemberUnlockBenefit] {
        [
            MemberUnlockBenefit(
                id: "natural-voice",
                symbol: "waveform",
                title: appState.localized("Natural Voice", "自然语音", "प्राकृतिक आवाज़"),
                subtitle: appState.localized("More natural spoken playback", "更自然的语音朗读", "और अधिक प्राकृतिक आवाज़ प्लेबैक")
            ),
            MemberUnlockBenefit(
                id: "widget",
                symbol: "square.grid.2x2.fill",
                title: appState.localized("Widget", "小组件", "विजेट"),
                subtitle: appState.localized("Quick access on your Home Screen", "主屏快速访问", "होम स्क्रीन पर त्वरित पहुंच")
            ),
            MemberUnlockBenefit(
                id: "member-icon",
                symbol: "app.badge.fill",
                title: appState.localized("Member Icon", "会员图标", "सदस्य आइकन"),
                subtitle: appState.localized("Unlock member-only app icon styles", "解锁会员专属图标样式", "केवल सदस्य आइकन शैली अनलॉक करें")
            )
        ]
    }
    private let horizontalPadding: CGFloat = 24
    private let planOptionRowHeight: CGFloat = 48
    private let planOptionSpacing: CGFloat = 8
    private let planOptionsAnimation = Animation.spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.12)
    private let termsOfUseURL = "https://hungry-land-732.notion.site/Terms-of-Use-32c52d9458a9802e9308c296fc8fd9d8?source=copy_link"
    private let privacyPolicyURL = "https://hungry-land-732.notion.site/Privacy-Policy-32c52d9458a980b6975cd6786df84199?source=copy_link"
    private var planOptionsExpandedHeight: CGFloat {
        let count = CGFloat(MemberPlan.allCases.count)
        let spacingCount = max(0, CGFloat(MemberPlan.allCases.count - 1))
        return (count * planOptionRowHeight) + (spacingCount * planOptionSpacing)
    }
    private var isDarkMode: Bool { colorScheme == .dark }

    private var backgroundColor: LinearGradient {
        AppColors.appBackgroundGradient(themeMode: appState.themeMode, isDarkMode: isDarkMode)
    }
    private var strokeColor: Color {
        isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
    private var primaryTextColor: Color {
        isDarkMode ? Color.white.opacity(0.92) : Color.black.opacity(0.82)
    }
    private var secondaryTextColor: Color {
        isDarkMode ? Color.white.opacity(0.56) : Color.black.opacity(0.46)
    }
    private var buttonColor: Color {
        isDarkMode ? Color.white.opacity(0.93) : Color.black.opacity(0.86)
    }
    private var buttonTextColor: Color {
        isDarkMode ? Color.black.opacity(0.90) : Color.white
    }
    private var planOptionBackgroundColor: Color {
        isDarkMode
            ? Color(red: 0.33, green: 0.37, blue: 0.52).opacity(0.78)
            : Color(red: 0.90, green: 0.91, blue: 0.95)
    }
    private var planOptionBorderColor: Color {
        isDarkMode ? Color.white.opacity(0.09) : Color.black.opacity(0.05)
    }
    private var planSelectedIconColor: Color {
        isDarkMode ? Color.white.opacity(0.95) : Color.black.opacity(0.85)
    }
    private var planUnselectedIconColor: Color {
        isDarkMode ? Color.white.opacity(0.86) : Color.black.opacity(0.62)
    }
    private var legalDotColor: Color {
        isDarkMode ? Color.white.opacity(0.30) : Color.black.opacity(0.32)
    }
    private var selectedProduct: Product? {
        storeKitManager.product(for: selectedPlan.storeProduct)
    }
    private var selectedPlanPriceText: String {
        priceText(for: selectedPlan)
    }
    private var selectedPlanDetailText: String {
        detailText(for: selectedPlan)
    }
    private var purchaseButtonTitle: String {
        if storeKitManager.memberUnlocked {
            return appState.localized("Unlocked", "已解锁", "अनलॉक")
        }
        if storeKitManager.isPerformingStoreAction {
            return appState.localized("Connecting...", "连接中...", "कनेक्ट हो रहा है...")
        }
        if storeKitManager.isLoadingProducts && selectedProduct == nil {
            return appState.localized("Loading...", "加载中...", "लोड हो रहा है...")
        }
        return appState.localized("Continue", "继续", "जारी रखें")
    }
    private var isPurchaseButtonDisabled: Bool {
        storeKitManager.memberUnlocked ||
        storeKitManager.isPerformingStoreAction ||
        (storeKitManager.isLoadingProducts && selectedProduct == nil)
    }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width - horizontalPadding * 2
            let maxContentWidth = availableWidth.isFinite ? min(max(availableWidth, 0), 430) : 0

            ZStack {
                ThemedBackgroundView(
                    themeMode: appState.themeMode,
                    isDarkMode: isDarkMode
                )

                VStack(spacing: 0) {
                    Spacer().frame(height: 18)
                    benefitsSection(maxContentWidth: maxContentWidth)
                    Spacer().frame(height: 12)
                    planAndCtaSection(maxContentWidth: maxContentWidth)
                    Spacer().frame(height: 6)
                    legalSection(bottomInset: max(4, proxy.safeAreaInsets.bottom - 8))
                }
            }
        }
        .task {
            await storeKitManager.refreshProductsForCurrentStorefront()
            await storeKitManager.syncMembershipStatus()
            if let purchasedProduct = storeKitManager.purchasedProduct {
                selectedPlan = plan(for: purchasedProduct)
            }
        }
        .alert(storeAlertTitle, isPresented: $showingStoreAlert) {
            Button(appState.localized("OK", "好的", "ठीक है"), role: .cancel) {}
        } message: {
            Text(storeAlertMessage)
        }
    }

    @ViewBuilder
    private func benefitsSection(maxContentWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(benefits.enumerated()), id: \.element.id) { index, benefit in
                HStack(spacing: 14) {
                    Image(systemName: benefit.symbol)
                        .font(.system(size: 19, weight: .regular, design: .default))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(benefit.title)
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundStyle(primaryTextColor)

                        Text(benefit.subtitle)
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundStyle(secondaryTextColor)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)

                if index < benefits.count - 1 {
                    Rectangle()
                        .fill(strokeColor)
                        .frame(height: 1)
                        .padding(.leading, 38)
                }
            }
        }
        .frame(maxWidth: maxContentWidth)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func planAndCtaSection(maxContentWidth: CGFloat) -> some View {
        VStack(spacing: 14) {
            inlinePlanOptionsSection(maxContentWidth: maxContentWidth)
                .frame(maxHeight: showingAllPlans ? planOptionsExpandedHeight : 0, alignment: .top)
                .clipped()
                .opacity(showingAllPlans ? 1 : 0)
                .scaleEffect(y: showingAllPlans ? 1 : 0.96, anchor: .top)
                .allowsHitTesting(showingAllPlans)

            HStack(spacing: 12) {
                Text(selectedPlanPriceText)
                    .font(.system(size: 17, weight: .semibold, design: .default))
                    .foregroundStyle(primaryTextColor)

                Spacer(minLength: 12)

                Button(action: togglePlanOptions) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 15, weight: .medium))
                            .rotationEffect(.degrees(showingAllPlans ? 180 : 0))
                        Text(showingAllPlans ? "Hide all plans" : "Show all plans")
                            .font(.system(size: 15, weight: .regular, design: .default))
                    }
                    .foregroundStyle(secondaryTextColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .frame(height: 40)
            .frame(maxWidth: maxContentWidth)

            Text(selectedPlanDetailText)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(secondaryTextColor)

            Button {
                purchaseSelectedPlan()
            } label: {
                Text(purchaseButtonTitle)
                    .font(.system(size: 17, weight: .semibold, design: .default))
                    .foregroundStyle(buttonTextColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 68)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(buttonColor)
                    )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: maxContentWidth)
            .disabled(isPurchaseButtonDisabled)

        }
        .padding(.horizontal, horizontalPadding)
        .animation(planOptionsAnimation, value: showingAllPlans)
    }

    @ViewBuilder
    private func inlinePlanOptionsSection(maxContentWidth: CGFloat) -> some View {
        VStack(spacing: planOptionSpacing) {
            ForEach(MemberPlan.allCases) { plan in
                Button {
                    selectedPlan = plan
                    withAnimation(planOptionsAnimation) {
                        showingAllPlans = false
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: plan == selectedPlan ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24, weight: .regular, design: .default))
                            .foregroundStyle(plan == selectedPlan ? planSelectedIconColor : planUnselectedIconColor)

                        Text(priceText(for: plan))
                            .font(.system(size: 16, weight: .regular, design: .default))
                            .foregroundStyle(primaryTextColor)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity)
                    .frame(height: planOptionRowHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(plan == selectedPlan
                                    ? Color.white.opacity(isDarkMode ? 0.30 : 0.50)
                                    : Color.white.opacity(isDarkMode ? 0.10 : 0.30),
                                    lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: maxContentWidth)
    }

    @ViewBuilder
    private func legalSection(bottomInset: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button(action: openTermsOfUse) {
                Text(appState.localized("Terms of Use", "使用条款", "उपयोग की शर्तें"))
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(secondaryTextColor)
            }
            .buttonStyle(.plain)

            Text("·")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(legalDotColor)

            Button(action: restorePurchases) {
                Text(appState.localized("Restore Purchases", "恢复购买", "खरीदारी बहाल करें"))
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(secondaryTextColor)
            }
            .buttonStyle(.plain)

            Text("·")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(legalDotColor)

            Button(action: openPrivacyPolicy) {
                Text(appState.localized("Privacy Policy", "隐私政策", "गोपनीयता नीति"))
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(secondaryTextColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, bottomInset)
    }

    private func togglePlanOptions() {
        withAnimation(planOptionsAnimation) {
            showingAllPlans.toggle()
        }
    }

    private func plan(for product: StoreKitManager.MemberProduct) -> MemberPlan {
        switch product {
        case .monthly:
            return .monthly
        case .yearly:
            return .yearly
        case .lifetime:
            return .lifetime
        }
    }

    private func priceText(for plan: MemberPlan) -> String {
        guard let product = storeKitManager.product(for: plan.storeProduct) else {
            switch plan {
            case .monthly:
                return appState.localized("Monthly Plan", "月度会员", "मासिक प्लान")
            case .yearly:
                return appState.localized("Yearly Plan", "年度会员", "वार्षिक प्लान")
            case .lifetime:
                return appState.localized("Lifetime Access", "终身会员", "लाइफटाइम एक्सेस")
            }
        }

        switch plan {
        case .monthly:
            return appState.localized(
                "\(product.displayPrice) / Month",
                "\(product.displayPrice) / 月",
                "\(product.displayPrice) / माह"
            )
        case .yearly:
            return appState.localized(
                "\(product.displayPrice) / Year",
                "\(product.displayPrice) / 年",
                "\(product.displayPrice) / वर्ष"
            )
        case .lifetime:
            return appState.localized(
                "\(product.displayPrice) / Lifetime",
                "\(product.displayPrice) / 终身",
                "\(product.displayPrice) / लाइफटाइम"
            )
        }
    }

    private func detailText(for plan: MemberPlan) -> String {
        if let product = storeKitManager.product(for: plan.storeProduct) {
            switch plan {
            case .monthly:
                if product.subscription?.introductoryOffer != nil {
                    return appState.localized(
                        "Includes a free trial, then \(product.displayPrice) every month.",
                        "含免费试用，之后每月 \(product.displayPrice)。",
                        "इसमें फ्री ट्रायल शामिल है, फिर हर महीने \(product.displayPrice)।"
                    )
                }
                return appState.localized(
                    "Billed monthly at \(product.displayPrice).",
                    "按月计费，每月 \(product.displayPrice)。",
                    "हर महीने \(product.displayPrice) बिल किया जाएगा।"
                )
            case .yearly:
                if product.subscription?.introductoryOffer != nil {
                    return appState.localized(
                        "Includes a free trial, then \(product.displayPrice) every year.",
                        "含免费试用，之后每年 \(product.displayPrice)。",
                        "इसमें फ्री ट्रायल शामिल है, फिर हर साल \(product.displayPrice)।"
                    )
                }
                return appState.localized(
                    "Billed yearly at \(product.displayPrice).",
                    "按年计费，每年 \(product.displayPrice)。",
                    "हर साल \(product.displayPrice) बिल किया जाएगा।"
                )
            case .lifetime:
                return appState.localized(
                    "One-time payment, lifetime access.",
                    "一次购买，终身使用。",
                    "एक बार भुगतान, लाइफटाइम एक्सेस।"
                )
            }
        }

        if storeKitManager.isLoadingProducts {
            return appState.localized(
                "Loading the latest App Store pricing...",
                "正在加载 App Store 最新价格...",
                "ऐप स्टोर की नवीनतम कीमतें लोड हो रही हैं..."
            )
        }

        return appState.localized(
            "App Store product unavailable. If this persists, verify the product ID in App Store Connect.",
            "App Store 商品暂不可用；如果持续出现，请检查 App Store Connect 里的 Product ID。",
            "ऐप स्टोर प्रोडक्ट उपलब्ध नहीं है। अगर यह बना रहे, तो App Store Connect में Product ID जांचें।"
        )
    }

    private func purchaseSelectedPlan() {
        Task {
            let outcome = await storeKitManager.purchase(selectedPlan.storeProduct)
            switch outcome {
            case .success:
                dismiss()
            case .pending:
                presentStoreAlert(
                    title: appState.localized("Purchase Pending", "购买处理中", "खरीदारी लंबित है"),
                    message: appState.localized(
                        "The App Store is still processing this purchase.",
                        "App Store 仍在处理这笔购买。",
                        "ऐप स्टोर अभी इस खरीदारी को प्रोसेस कर रहा है।"
                    )
                )
            case .cancelled:
                break
            case .failed(let message):
                presentStoreAlert(
                    title: appState.localized("Purchase Failed", "购买失败", "खरीदारी असफल"),
                    message: message
                )
            }
        }
    }

    private func restorePurchases() {
        Task {
            let outcome = await storeKitManager.restorePurchases()
            switch outcome {
            case .restored:
                dismiss()
            case .nothingToRestore:
                presentStoreAlert(
                    title: appState.localized("Nothing to Restore", "没有可恢复的购买", "बहाल करने के लिए कुछ नहीं है"),
                    message: appState.localized(
                        "No active membership purchase was found for this Apple ID.",
                        "当前 Apple ID 下没有找到可恢复的会员购买。",
                        "इस Apple ID के लिए कोई सक्रिय सदस्यता खरीदारी नहीं मिली।"
                    )
                )
            case .failed(let message):
                presentStoreAlert(
                    title: appState.localized("Restore Failed", "恢复失败", "बहाली असफल"),
                    message: message
                )
            }
        }
    }

    private func openTermsOfUse() {
        guard let url = URL(string: termsOfUseURL) else { return }
        openURL(url)
    }

    private func openPrivacyPolicy() {
        guard let url = URL(string: privacyPolicyURL) else { return }
        openURL(url)
    }

    private func presentStoreAlert(title: String, message: String) {
        storeAlertTitle = title
        storeAlertMessage = message
        showingStoreAlert = true
    }
}

private struct MemberUnlockBenefit: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let subtitle: String
}
