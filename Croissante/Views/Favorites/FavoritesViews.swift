import SwiftUI
import Combine
import AVFoundation
#if os(iOS)
import UIKit
import CoreMotion
#endif


enum FavoriteCarouselMotion {
    static let carouselDragDistanceFactor: CGFloat = 0.46
    static let settleSpringResponse: Double = 0.48
    static let settleSpringDamping: Double = 0.88
    static let dockPointerSpringResponse: Double = 0.24
    static let dockPointerSpringDamping: Double = 0.68
    static let dockStartAngleDegrees: Double = 232
    static let dockEndAngleDegrees: Double = 308
    private static let edgeRubberBandIndexLimit: CGFloat = 0.14
    private static let maxProjectedIndexTravel: CGFloat = 2.8

    static func indexDelta(for translationX: CGFloat, width: CGFloat) -> CGFloat {
        -translationX / max(width * carouselDragDistanceFactor, 1)
    }

    static func clampedIndex(_ index: CGFloat, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        return min(max(index, 0), CGFloat(count - 1))
    }

    static func nearestIndex(for index: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let rounded = Int(index.rounded(.toNearestOrAwayFromZero))
        return min(max(rounded, 0), count - 1)
    }

    static func rubberBandedIndex(proposed: CGFloat, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        let maxIndex = CGFloat(count - 1)
        if proposed < 0 {
            return -rubberBandedOvershoot(-proposed)
        }
        if proposed > maxIndex {
            return maxIndex + rubberBandedOvershoot(proposed - maxIndex)
        }
        return proposed
    }

    static func settledIndex(
        startIndex: CGFloat,
        translation: CGFloat,
        predicted: CGFloat,
        width: CGFloat,
        count: Int
    ) -> CGFloat {
        guard count > 1 else { return 0 }
        let currentIndex = clampedIndex(startIndex + indexDelta(for: translation, width: width), count: count)
        let projectedIndex = clampedIndex(startIndex + indexDelta(for: predicted, width: width), count: count)
        let travel = min(
            max(projectedIndex - currentIndex, -maxProjectedIndexTravel),
            maxProjectedIndexTravel
        )
        let limitedProjectedIndex = clampedIndex(currentIndex + travel, count: count)
        // Let drag motion stay continuous, but always settle onto a real card.
        return CGFloat(nearestIndex(for: limitedProjectedIndex, count: count))
    }

    static func visibleIndexRange(centerIndex: CGFloat, count: Int, radius: Int = 3) -> ClosedRange<Int>? {
        guard count > 0 else { return nil }
        let center = nearestIndex(for: centerIndex, count: count)
        let lower = max(0, center - radius)
        let upper = min(count - 1, center + radius)
        return lower...upper
    }

    static func dockTrackRadius(for width: CGFloat) -> CGFloat {
        min(width * 0.62, 620)
    }

    static func dockIndex(forLocationX locationX: CGFloat, width: CGFloat, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        let radius = max(dockTrackRadius(for: width), 1)
        let centerX = width / 2
        let startAngle = dockStartAngleDegrees * .pi / 180
        let endAngle = dockEndAngleDegrees * .pi / 180
        let startCos = cos(startAngle)
        let endCos = cos(endAngle)
        let minCos = min(startCos, endCos)
        let maxCos = max(startCos, endCos)
        let normalizedX = min(max(Double((locationX - centerX) / radius), minCos), maxCos)
        let selectedAngle = (2 * .pi) - acos(normalizedX)
        let progress = (selectedAngle - startAngle) / max(endAngle - startAngle, 0.001)
        let rawIndex = CGFloat(progress) * CGFloat(count - 1)
        return clampedIndex(rawIndex, count: count)
    }

    private static func rubberBandedOvershoot(_ overshoot: CGFloat) -> CGFloat {
        let t = min(1, overshoot / max(edgeRubberBandIndexLimit, 0.001))
        return edgeRubberBandIndexLimit * (1 - cos(t * .pi * 0.5))
    }
}

enum FavoritesSearchPhase: Equatable {
    case browsing
    case enteringSearch
    case active
}

struct FavoritesCollectionView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var catalogWordsSnapshot: [SimpleWord] = []

    private var isDarkMode: Bool { colorScheme == .dark }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    ThemedBackgroundView(themeMode: appState.themeMode, isDarkMode: isDarkMode)
                    FavoritesDottedBackdrop(isDarkMode: isDarkMode)
                        .opacity(isDarkMode ? 0.72 : 0.42)
                        .allowsHitTesting(false)

                    if catalogWordsSnapshot.isEmpty {
                        DiscoverEmptyStateView(
                            title: appState.localized("No favorites yet", "暂无收藏"),
                            subtitle: appState.localized("Tap the graduation cap on a card to save words here.", "在卡片上点击学位帽即可收藏单词。")
                        )
                        .padding(.horizontal, 24)
                    } else {
                        FavoritesInteractiveRoot(
                            catalogWords: catalogWordsSnapshot,
                            onDismiss: { dismiss() }
                        )
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .onAppear(perform: refreshCatalogSnapshot)
        .onChange(of: favoritesStore.favoriteWordIds) { _, _ in refreshCatalogSnapshot() }
        .onReceive(appState.$words) { _ in refreshCatalogSnapshot() }
    }

    private func refreshCatalogSnapshot() {
        catalogWordsSnapshot = favoritesStore.resolvedWords(from: appState.words)
    }
}

struct FavoritesInteractiveRoot: View {
    let catalogWords: [SimpleWord]
    let onDismiss: () -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var carouselIndex: CGFloat = 0
    @State private var carouselDragStartIndex: CGFloat?
    @State private var searchPhase: FavoritesSearchPhase = .browsing
    @State private var searchText = ""
    @State private var hasAppliedInitialSelection = false
    @State private var lastDockGearHapticIndex: Int?
    @State private var isCarouselSettling = false
    @State private var carouselSettleToken = 0
    @State private var searchTransitionToken = 0
    @FocusState private var isSearchFieldFocused: Bool

    private var isDarkMode: Bool { colorScheme == .dark }
    private var isSearchPresented: Bool { searchPhase != .browsing }
    private var isBrowsingFavorites: Bool { searchPhase == .browsing }
    private var isEnteringSearch: Bool { searchPhase == .enteringSearch }
    private var isSearchActive: Bool { searchPhase == .active }
    private var searchScatterDuration: TimeInterval { 0.24 }
    private var searchFocusDelay: TimeInterval { 0.05 }

    private var selectedIndex: Int {
        FavoriteCarouselMotion.nearestIndex(for: carouselIndex, count: displayedWords.count)
    }

    private var displayedWords: [SimpleWord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return catalogWords }
        return catalogWords.filter { word in
            [
                word.displayWord,
                word.word,
                word.translationEn,
                word.translationZh,
                word.tag
            ]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var displayedWordIds: [String] {
        displayedWords.map(\.id)
    }

    var body: some View {
        GeometryReader { geo in
            favoritesShowcase(size: geo.size)
        }
    }

    private func favoritesShowcase(size: CGSize) -> some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 18)

                if displayedWords.isEmpty && isBrowsingFavorites {
                    Spacer(minLength: 20)
                    DiscoverEmptyStateView(
                        title: appState.localized("No matches", "没有匹配结果"),
                        subtitle: appState.localized("Try another favorite word.", "试试搜索另一个收藏单词。")
                    )
                    .padding(.horizontal, 28)
                    Spacer(minLength: 22)
                } else if !isSearchActive {
                    Spacer(minLength: 16)
                    FavoritesCarouselView(
                        words: displayedWords,
                        carouselIndex: carouselIndex,
                        isDarkMode: isDarkMode,
                        isSettling: isCarouselSettling,
                        isExitingForSearch: isEnteringSearch,
                        onDragChanged: updateCarouselDrag,
                        onDragEnded: finishCarouselDrag
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: max(300, min(size.height * 0.48, 430)))
                    Spacer(minLength: 8)
                } else {
                    Spacer(minLength: 0)
                }

                if !isSearchActive {
                    FavoritesControlDock(
                        count: displayedWords.count,
                        carouselIndex: carouselIndex,
                        isDarkMode: isDarkMode,
                        onScrubIndexChanged: updateDockScrub,
                        onScrubIndexEnded: finishDockScrub,
                        onDismiss: onDismiss,
                        onToggleSearch: toggleSearch,
                        onToggleFavorite: removeSelectedFavorite
                    )
                    .frame(height: 176)
                    .padding(.horizontal, -8)
                    .opacity(isBrowsingFavorites ? 1 : 0)
                    .scaleEffect(isBrowsingFavorites ? 1 : 0.94, anchor: .bottom)
                    .offset(y: isBrowsingFavorites ? 0 : 54)
                    .allowsHitTesting(isBrowsingFavorites)
                }
            }
            .allowsHitTesting(isBrowsingFavorites)
            .zIndex(0)

            if isSearchActive {
                searchResultsLayer(size: size)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(1)
            }

            if isSearchPresented {
                searchBar
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: searchScatterDuration), value: searchPhase)
        .frame(width: size.width, height: size.height, alignment: .top)
        .onAppear(perform: resetInitialSelectionToMiddle)
        .onChange(of: displayedWordIds) { _, _ in
            if hasAppliedInitialSelection {
                clampCarouselIndex()
            } else {
                applyInitialSelectionIfNeeded()
            }
        }
        .onChange(of: searchText) { _, _ in
            clampCarouselIndex()
        }
        .onChange(of: selectedIndex) { _, _ in
            ElevenLabsTTSService.stopPlayback()
        }
        .onDisappear {
            searchTransitionToken += 1
            isSearchFieldFocused = false
            ElevenLabsTTSService.stopPlayback()
        }
    }

    private func searchResultsLayer(size: CGSize) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 82)

            if displayedWords.isEmpty {
                Spacer(minLength: 24)
                DiscoverEmptyStateView(
                    title: appState.localized("No matches", "没有匹配结果"),
                    subtitle: appState.localized("Try another favorite word.", "试试搜索另一个收藏单词。")
                )
                .padding(.horizontal, 28)
                Spacer(minLength: 24)
            } else {
                List {
                    ForEach(displayedWords) { word in
                        FavoriteSearchResultRow(
                            word: word,
                            isDarkMode: isDarkMode
                        ) {
                            selectSearchResult(word)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.immediately)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 34)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
            searchTextField

            if !searchText.isEmpty {
                clearSearchButton
            }

            closeSearchButton
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(searchBarForeground)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(searchBarBackground)
        .overlay(searchBarBorder)
    }

    private var searchTextField: some View {
        let placeholder = appState.localized("Search favorites", "搜索收藏")
        return TextField(placeholder, text: $searchText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isSearchFieldFocused)
    }

    private var clearSearchButton: some View {
        Button {
            FeedbackService.cardMetaButtonTap()
            searchText = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appState.localized("Clear search", "清除搜索"))
    }

    private var closeSearchButton: some View {
        Button {
            FeedbackService.cardMetaButtonTap()
            exitSearch()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appState.localized("Close search", "关闭搜索"))
    }

    private var searchBarForeground: Color {
        isDarkMode ? Color.white.opacity(0.76) : Color.black.opacity(0.64)
    }

    private var searchBarBackground: some View {
        Capsule(style: .continuous)
            .fill(isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.055))
    }

    private var searchBarBorder: some View {
        Capsule(style: .continuous)
            .stroke(isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 1)
    }

    private func updateCarouselDrag(_ translationX: CGFloat, width: CGFloat) {
        guard displayedWords.count > 1 else {
            carouselIndex = 0
            resetDockGearHaptic()
            return
        }

        if isCarouselSettling {
            carouselSettleToken += 1
            isCarouselSettling = false
        }

        let startIndex = carouselDragStartIndex ?? FavoriteCarouselMotion.clampedIndex(
            carouselIndex,
            count: displayedWords.count
        )
        carouselDragStartIndex = startIndex
        let proposedIndex = startIndex + FavoriteCarouselMotion.indexDelta(for: translationX, width: width)
        let boundedIndex = FavoriteCarouselMotion.rubberBandedIndex(
            proposed: proposedIndex,
            count: displayedWords.count
        )
        carouselIndex = boundedIndex
        updateDockGearHaptic(for: boundedIndex)
    }

    private func finishCarouselDrag(translation: CGFloat, predicted: CGFloat, width: CGFloat) {
        guard displayedWords.count > 1 else {
            carouselIndex = 0
            carouselDragStartIndex = nil
            resetDockGearHaptic()
            return
        }

        let startIndex = carouselDragStartIndex ?? carouselIndex
        let originalIndex = FavoriteCarouselMotion.nearestIndex(for: startIndex, count: displayedWords.count)
        let targetIndex = FavoriteCarouselMotion.settledIndex(
            startIndex: startIndex,
            translation: translation,
            predicted: predicted,
            width: width,
            count: displayedWords.count
        )
        let targetNearestIndex = FavoriteCarouselMotion.nearestIndex(for: targetIndex, count: displayedWords.count)

        carouselDragStartIndex = nil
        settleCarousel(to: targetIndex)
        triggerDockGearHapticIfNeeded(to: targetNearestIndex, from: originalIndex)
        resetDockGearHaptic()
    }

    private func updateDockScrub(to index: CGFloat) {
        guard displayedWords.count > 1 else {
            carouselIndex = 0
            resetDockGearHaptic()
            return
        }

        if isCarouselSettling {
            carouselSettleToken += 1
            isCarouselSettling = false
        }

        carouselDragStartIndex = nil
        let boundedIndex = FavoriteCarouselMotion.clampedIndex(index, count: displayedWords.count)
        carouselIndex = boundedIndex
        updateDockGearHaptic(for: boundedIndex)
    }

    private func finishDockScrub(index: CGFloat, predictedIndex: CGFloat) {
        guard displayedWords.count > 1 else {
            carouselIndex = 0
            carouselDragStartIndex = nil
            resetDockGearHaptic()
            return
        }

        carouselDragStartIndex = nil
        let currentIndex = FavoriteCarouselMotion.clampedIndex(index, count: displayedWords.count)
        let originalIndex = FavoriteCarouselMotion.nearestIndex(for: currentIndex, count: displayedWords.count)
        let targetIndex = CGFloat(FavoriteCarouselMotion.nearestIndex(for: predictedIndex, count: displayedWords.count))
        let targetNearestIndex = FavoriteCarouselMotion.nearestIndex(for: targetIndex, count: displayedWords.count)

        settleCarousel(to: targetIndex)
        triggerDockGearHapticIfNeeded(to: targetNearestIndex, from: originalIndex)
        resetDockGearHaptic()
    }

    private func updateDockGearHaptic(for index: CGFloat) {
        guard displayedWords.count > 1 else {
            resetDockGearHaptic()
            return
        }

        let hapticIndex = FavoriteCarouselMotion.nearestIndex(for: index, count: displayedWords.count)

        guard let previousIndex = lastDockGearHapticIndex else {
            FeedbackService.prepareInteractive()
            FeedbackService.gearHapticTick()
            lastDockGearHapticIndex = hapticIndex
            return
        }

        let steps = abs(hapticIndex - previousIndex)
        guard steps > 0 else { return }
        FeedbackService.gearHapticTick(steps: steps)
        lastDockGearHapticIndex = hapticIndex
    }

    private func triggerDockGearHapticIfNeeded(to committedIndex: Int, from originalIndex: Int) {
        guard committedIndex != originalIndex else { return }
        let previousIndex = lastDockGearHapticIndex ?? originalIndex
        let steps = abs(committedIndex - previousIndex)
        guard steps > 0 else { return }
        FeedbackService.gearHapticTick(steps: steps)
    }

    private func resetDockGearHaptic() {
        lastDockGearHapticIndex = nil
    }

    private func settleCarousel(to targetIndex: CGFloat) {
        let count = displayedWords.count
        guard count > 1 else {
            carouselIndex = 0
            isCarouselSettling = false
            return
        }

        carouselSettleToken += 1
        let token = carouselSettleToken
        let boundedIndex = FavoriteCarouselMotion.clampedIndex(targetIndex, count: count)
        isCarouselSettling = true

        withAnimation(
            .spring(
                response: FavoriteCarouselMotion.settleSpringResponse,
                dampingFraction: FavoriteCarouselMotion.settleSpringDamping
            ),
            completionCriteria: .logicallyComplete
        ) {
            carouselIndex = boundedIndex
        } completion: {
            finishCarouselSettle(token: token)
        }
    }

    private func finishCarouselSettle(token: Int) {
        guard carouselSettleToken == token else { return }
        carouselIndex = CGFloat(FavoriteCarouselMotion.nearestIndex(for: carouselIndex, count: displayedWords.count))
        isCarouselSettling = false
    }

    private func toggleSearch() {
        if isBrowsingFavorites {
            beginSearch()
        } else {
            exitSearch()
        }
    }

    private func beginSearch() {
        guard isBrowsingFavorites else { return }
        searchTransitionToken += 1
        let token = searchTransitionToken

        ElevenLabsTTSService.stopPlayback()
        FeedbackService.prepareInteractive()
        FeedbackService.gearHapticTick()
        carouselDragStartIndex = nil
        resetDockGearHaptic()

        withAnimation(.easeOut(duration: searchScatterDuration)) {
            searchPhase = .enteringSearch
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + searchScatterDuration) {
            guard searchTransitionToken == token, searchPhase == .enteringSearch else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                searchPhase = .active
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + searchFocusDelay) {
                guard searchTransitionToken == token, searchPhase == .active else { return }
                isSearchFieldFocused = true
            }
        }
    }

    private func exitSearch() {
        guard isSearchPresented else { return }
        searchTransitionToken += 1
        let targetIndex = restoredCatalogIndexForCurrentSearchSelection()

        isSearchFieldFocused = false
        withAnimation(
            .spring(
                response: FavoriteCarouselMotion.settleSpringResponse,
                dampingFraction: FavoriteCarouselMotion.settleSpringDamping
            )
        ) {
            searchText = ""
            searchPhase = .browsing
            carouselIndex = CGFloat(targetIndex)
        }
        clampCarouselIndex()
    }

    private func selectSearchResult(_ word: SimpleWord) {
        guard let targetIndex = catalogWords.firstIndex(where: { $0.id == word.id }) else { return }
        searchTransitionToken += 1

        isSearchFieldFocused = false
        withAnimation(
            .spring(
                response: FavoriteCarouselMotion.settleSpringResponse,
                dampingFraction: FavoriteCarouselMotion.settleSpringDamping
            )
        ) {
            searchText = ""
            searchPhase = .browsing
            carouselIndex = CGFloat(targetIndex)
        }
        clampCarouselIndex()
    }

    private func restoredCatalogIndexForCurrentSearchSelection() -> Int {
        guard !catalogWords.isEmpty else { return 0 }
        guard displayedWords.indices.contains(selectedIndex) else {
            return FavoriteCarouselMotion.nearestIndex(for: carouselIndex, count: catalogWords.count)
        }
        let selectedID = displayedWords[selectedIndex].id
        return catalogWords.firstIndex { $0.id == selectedID }
            ?? FavoriteCarouselMotion.nearestIndex(for: carouselIndex, count: catalogWords.count)
    }

    private func removeSelectedFavorite() {
        guard displayedWords.indices.contains(selectedIndex) else { return }
        favoritesStore.toggleFavorite(wordId: displayedWords[selectedIndex].id)
        clampCarouselIndex()
    }

    private func applyInitialSelectionIfNeeded() {
        guard !hasAppliedInitialSelection else {
            clampCarouselIndex()
            return
        }

        resetInitialSelectionToMiddle()
    }

    private func resetInitialSelectionToMiddle() {
        let count = displayedWords.count
        guard count > 0 else {
            carouselIndex = 0
            carouselDragStartIndex = nil
            hasAppliedInitialSelection = true
            return
        }

        carouselIndex = CGFloat(initialMiddleIndex(for: count))
        carouselDragStartIndex = nil
        hasAppliedInitialSelection = true
    }

    private func initialMiddleIndex(for count: Int) -> Int {
        guard count > 1 else { return 0 }
        return (count - 1) / 2
    }

    private func clampCarouselIndex() {
        let count = displayedWords.count
        carouselSettleToken += 1
        carouselDragStartIndex = nil
        guard count > 0 else {
            carouselIndex = 0
            isCarouselSettling = false
            resetDockGearHaptic()
            return
        }
        carouselIndex = FavoriteCarouselMotion.clampedIndex(carouselIndex, count: count)
        isCarouselSettling = false
        resetDockGearHaptic()
    }

}

struct FavoriteSearchResultRow: View {
    let word: SimpleWord
    let isDarkMode: Bool
    let action: () -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var favoritesStore: FavoritesStore

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(word.word)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(2)

                Text(appState.translationText(for: word))
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 205, alignment: .trailing)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(word.word)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(role: .destructive) {
                removeFromFavorites()
            } label: {
                Label(appState.localized("Remove", "移除"), systemImage: "trash")
            }
            .tint(.red)
        }
    }

    private var primaryTextColor: Color {
        isDarkMode ? AppColors.nocturneTextPrimary : Color.black.opacity(0.82)
    }

    private var secondaryTextColor: Color {
        isDarkMode ? AppColors.nocturneTextSecondary : Color.black.opacity(0.44)
    }

    private func removeFromFavorites() {
        withAnimation(.easeInOut(duration: 0.20)) {
            favoritesStore.toggleFavorite(wordId: word.id)
        }
    }
}

struct FavoriteCardStaticPreview: View {
    let word: SimpleWord
    let layoutCardWidth: CGFloat
    let layoutCardContentHeight: CGFloat
    let contentOpacity: Double
    let isDarkMode: Bool
    var isInteractive: Bool = false

    @EnvironmentObject private var appState: AppState

    private var titleTapAction: (() -> Void)? {
        guard isInteractive else { return nil }
        return { speakWord() }
    }

    private var detailTapAction: (() -> Void)? {
        guard isInteractive else { return nil }
        return { speakExampleSentence() }
    }

    var body: some View {
        let body = CardBody(
            word: word,
            cardWidth: layoutCardWidth,
            cardHeight: layoutCardContentHeight,
            detailProgress: 1,
            contentOpacity: contentOpacity,
            audioReactiveDividerEnabled: isInteractive,
            isEditingLocalizedContent: false,
            onTitleTap: titleTapAction,
            onDetailTap: detailTapAction
        )
        body
    }

    private func speakWord() {
        let trimmedWord = word.displayWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }

        ElevenLabsTTSService.stopPlayback()
        ElevenLabsTTSService.speakText(
            trimmedWord,
            language: "fr-FR",
            contentType: .word,
            playbackID: word.id
        )
    }

    private func speakExampleSentence() {
        let trimmedExample = appState.frenchExampleText(for: word)
        guard !trimmedExample.isEmpty else { return }

        ElevenLabsTTSService.stopPlayback()
        let cachePolicy: ElevenLabsTTSService.CachePolicy = appState.hasUserWordContentOverride(
            for: word,
            field: .exampleFr
        ) ? .userOverride : .official
        ElevenLabsTTSService.speakText(
            trimmedExample,
            language: "fr-FR",
            contentType: .sentence,
            cachePolicy: cachePolicy,
            playbackID: word.id
        )
    }
}

struct FavoritesCarouselView: View {
    let words: [SimpleWord]
    let carouselIndex: CGFloat
    let isDarkMode: Bool
    let isSettling: Bool
    let isExitingForSearch: Bool
    let onDragChanged: (_ translationX: CGFloat, _ width: CGFloat) -> Void
    let onDragEnded: (_ translationX: CGFloat, _ predictedTranslationX: CGFloat, _ width: CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            let viewportWidth = max(geo.size.width, 1)
            let displayCardWidth = min(max(viewportWidth * 0.80, 268), 352)
            let layoutCardWidth = min(max(displayCardWidth / 0.76, displayCardWidth), 380)
            let cardContentScale = displayCardWidth / max(layoutCardWidth, 1)
            let layoutCardContentHeight = DiscoverCardLayout.cardHeight(forCardWidth: layoutCardWidth)
            let layoutCardVisualHeight = layoutCardContentHeight + 48
            let displayCardVisualHeight = layoutCardVisualHeight * cardContentScale
            let nearestIndex = CGFloat(FavoriteCarouselMotion.nearestIndex(for: carouselIndex, count: words.count))
            let isInMotion = isSettling || abs(carouselIndex - nearestIndex) > 0.01

            ZStack {
                ForEach(carouselSlots(centerIndex: carouselIndex)) { slot in
                    let position = CGFloat(slot.index) - carouselIndex
                    FavoriteCarouselCard(
                        word: slot.word,
                        displayCardWidth: displayCardWidth,
                        displayCardVisualHeight: displayCardVisualHeight,
                        layoutCardWidth: layoutCardWidth,
                        layoutCardContentHeight: layoutCardContentHeight,
                        layoutCardVisualHeight: layoutCardVisualHeight,
                        cardContentScale: cardContentScale,
                        isDarkMode: isDarkMode,
                        position: position,
                        isInMotion: isInMotion,
                        isExitingForSearch: isExitingForSearch
                    )
                    .zIndex(Double(slot.index))
                }
            }
            .offset(y: -min(34, viewportWidth * 0.075))
            .frame(width: viewportWidth, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard words.count > 1 else { return }
                        onDragChanged(value.translation.width, viewportWidth)
                    }
                    .onEnded { value in
                        guard words.count > 1 else {
                            onDragEnded(0, 0, viewportWidth)
                            return
                        }
                        onDragEnded(
                            value.translation.width,
                            value.predictedEndTranslation.width,
                            viewportWidth
                        )
                    }
            )
        }
    }

    private func carouselSlots(centerIndex: CGFloat) -> [FavoriteCarouselSlot] {
        guard let range = FavoriteCarouselMotion.visibleIndexRange(centerIndex: centerIndex, count: words.count) else {
            return []
        }
        return range.map { FavoriteCarouselSlot(word: words[$0], index: $0) }
    }
}

struct FavoriteCarouselSlot: Identifiable {
    let word: SimpleWord
    let index: Int

    var id: String { word.id }
}

struct FavoriteCarouselCard: View {
    let word: SimpleWord
    let displayCardWidth: CGFloat
    let displayCardVisualHeight: CGFloat
    let layoutCardWidth: CGFloat
    let layoutCardContentHeight: CGFloat
    let layoutCardVisualHeight: CGFloat
    let cardContentScale: CGFloat
    let isDarkMode: Bool
    /// Continuous fan position. Integer values are the resting slots:
    /// 0 = current center card, -1/1 = side cards, -2/2 = entry buffers.
    /// Fractional values are used during drag so the stack flows as one
    /// river instead of snapping between slots.
    let position: CGFloat
    let isInMotion: Bool
    let isExitingForSearch: Bool

    // MARK: - Fan geometry (all functions of `position`)

    private var arcStepDegrees: Double { 24.0 }

    private var arcAngleRadians: CGFloat {
        CGFloat(position * arcStepDegrees * .pi / 180)
    }

    private var fanArcRadius: CGFloat {
        max(displayCardWidth * 1.90, 560)
    }

    private var fanXOffset: CGFloat {
        sin(arcAngleRadians) * fanArcRadius
    }

    private var fanMaxYOffset: CGFloat {
        min(50, max(36, displayCardWidth * 0.14))
    }

    private var rawFanYOffset: CGFloat {
        min(fanArcRadius * (1 - cos(arcAngleRadians)), fanMaxYOffset)
    }

    private var fanYOffsetProgress: CGFloat {
        let distance = abs(position)
        let liftFreeDistance: CGFloat = 0.72
        guard distance > liftFreeDistance else { return 0 }
        let progress = min(1, (distance - liftFreeDistance) / max(1 - liftFreeDistance, 0.001))
        return progress * progress * (3 - 2 * progress)
    }

    private var fanYOffset: CGFloat {
        rawFanYOffset * fanYOffsetProgress
    }

    private var fanRotationDegrees: Double {
        max(-36, min(36, Double(position) * arcStepDegrees))
    }

    private var shellOpacity: Double {
        let distance = abs(position)
        let fullOpacityLimit: CGFloat = 1.02
        let hiddenLimit: CGFloat = isInMotion ? 1.54 : 1.66
        if distance <= fullOpacityLimit { return 1.0 }
        if distance >= hiddenLimit { return 0 }
        let progress = Double((distance - fullOpacityLimit) / max(hiddenLimit - fullOpacityLimit, 0.001))
        let falloffExponent: Double = isInMotion ? 1.55 : 1.35
        return max(0, min(1, pow(1 - progress, falloffExponent)))
    }

    private var contentOpacity: Double {
        let floorOpacity: Double = isInMotion ? 0.30 : 0.40
        let fadePerStep: Double = isInMotion ? 0.42 : 0.32
        return max(floorOpacity, 1.0 - Double(abs(position)) * fadePerStep)
    }

    private var isInteractiveCard: Bool {
        !isInMotion && abs(position) < 0.5
    }

    private var searchExitXOffset: CGFloat {
        let distance = min(abs(position), 2.6)
        guard distance > 0.15 else { return 0 }
        let direction: CGFloat = position < 0 ? -1 : 1
        return direction * displayCardWidth * (0.28 + distance * 0.17)
    }

    private var searchExitYOffset: CGFloat {
        let distance = min(abs(position), 2.6)
        if distance < 0.35 {
            return -displayCardVisualHeight * 0.20
        }
        return -displayCardVisualHeight * 0.08 + distance * 18
    }

    private var searchExitRotationDegrees: Double {
        let distance = min(abs(position), 2.4)
        if distance < 0.35 {
            return position < 0 ? 5 : -5
        }
        return Double(position) * 10 + (position < 0 ? -8 : 8)
    }

    var body: some View {
        let core = ZStack(alignment: .bottom) {
            FavoriteCardStaticPreview(
                word: word,
                layoutCardWidth: layoutCardWidth,
                layoutCardContentHeight: layoutCardContentHeight,
                contentOpacity: contentOpacity,
                isDarkMode: isDarkMode,
                isInteractive: isInteractiveCard
            )
            .frame(width: layoutCardWidth, height: layoutCardVisualHeight)
            .scaleEffect(cardContentScale, anchor: .bottom)
        }
        .frame(width: displayCardWidth, height: displayCardVisualHeight, alignment: .bottom)
        .rotationEffect(
            .degrees(fanRotationDegrees + (isExitingForSearch ? searchExitRotationDegrees : 0)),
            anchor: .bottom
        )
        .offset(
            x: fanXOffset + (isExitingForSearch ? searchExitXOffset : 0),
            y: fanYOffset + (isExitingForSearch ? searchExitYOffset : 0)
        )
        .scaleEffect(isExitingForSearch ? 0.82 : 1, anchor: .bottom)

        core
        .opacity(isExitingForSearch ? 0 : shellOpacity)
        .allowsHitTesting(isInteractiveCard && !isExitingForSearch)
    }
}

struct FavoritesControlDock: View {
    let count: Int
    let carouselIndex: CGFloat
    let isDarkMode: Bool
    let onScrubIndexChanged: (_ index: CGFloat) -> Void
    let onScrubIndexEnded: (_ index: CGFloat, _ predictedIndex: CGFloat) -> Void
    let onDismiss: () -> Void
    let onToggleSearch: () -> Void
    let onToggleFavorite: () -> Void

    @EnvironmentObject private var appState: AppState

    private var canNavigate: Bool { count > 1 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                FavoritesDockTicks(
                    count: max(count, 1),
                    carouselIndex: carouselIndex,
                    isDarkMode: isDarkMode
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .offset(y: -12)
                .contentShape(Rectangle())
                .gesture(tickScrubGesture(width: geo.size.width))
                .allowsHitTesting(canNavigate)

                HStack {
                    FavoritesDockIconButton(
                        systemName: "magnifyingglass",
                        size: 48,
                        isDarkMode: isDarkMode,
                        accessibilityLabel: appState.localized("Search favorites", "搜索收藏"),
                        action: {
                            FeedbackService.cardMetaButtonTap()
                            onToggleSearch()
                        }
                    )

                    Spacer()

                    FavoritesDockIconButton(
                        systemName: "graduationcap.fill",
                        size: 48,
                        isDarkMode: isDarkMode,
                        isDisabled: count == 0,
                        accessibilityLabel: appState.localized("Remove from favorites", "移出收藏"),
                        action: onToggleFavorite
                    )
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 26)
                .zIndex(1)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func tickScrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canNavigate else { return }
                onScrubIndexChanged(
                    FavoriteCarouselMotion.dockIndex(
                        forLocationX: value.location.x,
                        width: width,
                        count: count
                    )
                )
            }
            .onEnded { value in
                guard canNavigate else {
                    onScrubIndexEnded(0, 0)
                    return
                }
                let index = FavoriteCarouselMotion.dockIndex(
                    forLocationX: value.location.x,
                    width: width,
                    count: count
                )
                let predictedIndex = FavoriteCarouselMotion.dockIndex(
                    forLocationX: value.predictedEndLocation.x,
                    width: width,
                    count: count
                )
                onScrubIndexEnded(index, predictedIndex)
            }
    }
}

struct FavoritesDockIconButton: View {
    let systemName: String
    let size: CGFloat
    let isDarkMode: Bool
    var isDisabled: Bool = false
    let accessibilityLabel: String
    let action: () -> Void

    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconFontSize, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .themedGlassSurface(themeMode: appState.themeMode, isDarkMode: isDarkMode, elevated: true)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.34 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconFontSize: CGFloat {
        size <= 44 ? 14 : 22
    }

    private var iconColor: Color {
        isDarkMode ? Color.white.opacity(0.88) : Color.black.opacity(0.76)
    }
}

struct FavoritesDockTicks: View {
    let count: Int
    let carouselIndex: CGFloat
    let isDarkMode: Bool

    var body: some View {
        FavoritesDockTicksCanvas(
            count: count,
            isDarkMode: isDarkMode,
            carouselIndex: carouselIndex
        )
        .animation(
            .spring(
                response: FavoriteCarouselMotion.dockPointerSpringResponse,
                dampingFraction: FavoriteCarouselMotion.dockPointerSpringDamping
            ),
            value: carouselIndex
        )
    }
}

struct FavoritesDockTicksCanvas: View, @MainActor Animatable {
    let count: Int
    let isDarkMode: Bool
    var carouselIndex: CGFloat

    var animatableData: CGFloat {
        get { carouselIndex }
        set { carouselIndex = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let trackRadius = FavoriteCarouselMotion.dockTrackRadius(for: size.width)
            let center = CGPoint(x: size.width / 2, y: trackRadius + 12)
            let startAngle = Angle.degrees(FavoriteCarouselMotion.dockStartAngleDegrees)
            let endAngle = Angle.degrees(FavoriteCarouselMotion.dockEndAngleDegrees)
            let angleSpan = endAngle.radians - startAngle.radians

            let tickIntervalCount = max(count - 1, 1)
            let tickSubdivisions = max(1, Int(ceil(48.0 / Double(tickIntervalCount))))
            let tickCount = tickIntervalCount * tickSubdivisions + 1
            let tickBaseInner = trackRadius - 2
            let tickBaseOuter = trackRadius + 2
            let trackColor = isDarkMode ? Color.white : Color.black

            let indexProgress: CGFloat
            if count > 1 {
                let clampedIndex = FavoriteCarouselMotion.clampedIndex(carouselIndex, count: count)
                indexProgress = clampedIndex / CGFloat(max(count - 1, 1))
            } else {
                indexProgress = 0.5
            }
            let unclampedSelectedAngle = startAngle.radians + angleSpan * Double(indexProgress)
            let selectedAngle = min(
                max(unclampedSelectedAngle, startAngle.radians),
                endAngle.radians
            )

            for tick in 0..<tickCount {
                let progress = Double(tick) / Double(max(tickCount - 1, 1))
                let angle = startAngle.radians + angleSpan * progress
                let isMajor = tick % tickSubdivisions == 0 || tick % 4 == 0

                let distanceToSelected = abs(angle - selectedAngle)
                let focusFalloff = max(0, 1 - distanceToSelected / 0.22)

                let lengthBoost = CGFloat(focusFalloff) * 6
                let innerRadius = tickBaseInner - (isMajor ? 4 : 2) - lengthBoost
                let outerRadius = tickBaseOuter + (isMajor ? 2 : 0) + lengthBoost * 0.5

                let inner = CGPoint(
                    x: center.x + cos(angle) * innerRadius,
                    y: center.y + sin(angle) * innerRadius
                )
                let outer = CGPoint(
                    x: center.x + cos(angle) * outerRadius,
                    y: center.y + sin(angle) * outerRadius
                )

                var tickPath = Path()
                tickPath.move(to: inner)
                tickPath.addLine(to: outer)

                let baseOpacity: Double = isDarkMode
                    ? (isMajor ? 0.48 : 0.30)
                    : (isMajor ? 0.55 : 0.32)
                let opacity = baseOpacity + focusFalloff * (isDarkMode ? 0.45 : 0.38)
                let lineWidth: CGFloat = isMajor ? 1.4 : 1.0

                context.stroke(
                    tickPath,
                    with: .color(trackColor.opacity(min(opacity, 1))),
                    lineWidth: lineWidth + CGFloat(focusFalloff) * 0.6
                )
            }

            let pointerInset: CGFloat = 12
            let pointerInner = CGPoint(
                x: center.x + cos(selectedAngle) * (trackRadius - pointerInset),
                y: center.y + sin(selectedAngle) * (trackRadius - pointerInset)
            )
            let pointerOuter = CGPoint(
                x: center.x + cos(selectedAngle) * (trackRadius + pointerInset),
                y: center.y + sin(selectedAngle) * (trackRadius + pointerInset)
            )
            var pointer = Path()
            pointer.move(to: pointerInner)
            pointer.addLine(to: pointerOuter)
            let pointerColor = Color(red: 0.08, green: 0.40, blue: 0.23)
            let pointerGlowColor = Color(red: 0.31, green: 0.82, blue: 0.49)

            let dotRadius: CGFloat = 3.2
            let dotCenter = CGPoint(
                x: center.x + cos(selectedAngle) * trackRadius,
                y: center.y + sin(selectedAngle) * trackRadius
            )
            let dotRect = CGRect(
                x: dotCenter.x - dotRadius,
                y: dotCenter.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )

            context.drawLayer { layer in
                layer.addFilter(.blur(radius: isDarkMode ? 3.5 : 2.9))
                layer.stroke(
                    pointer,
                    with: .color(pointerGlowColor.opacity(isDarkMode ? 0.48 : 0.35)),
                    lineWidth: 6.0
                )
                layer.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(pointerGlowColor.opacity(isDarkMode ? 0.42 : 0.30))
                )
            }

            context.stroke(pointer, with: .color(pointerColor.opacity(isDarkMode ? 0.99 : 0.95)), lineWidth: 2.3)
            context.fill(
                Path(ellipseIn: dotRect),
                with: .color(pointerColor.opacity(isDarkMode ? 0.99 : 0.95))
            )
        }
    }
}

struct FavoritesDottedBackdrop: View {
    let isDarkMode: Bool

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 18
            let columns = Int(size.width / spacing) + 2
            let rows = Int(size.height / spacing) + 2
            let color = isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.055)

            for row in 0..<rows {
                for column in 0..<columns {
                    let x = CGFloat(column) * spacing + (row.isMultiple(of: 2) ? 0 : spacing * 0.5)
                    let y = CGFloat(row) * spacing
                    let rect = CGRect(x: x, y: y, width: 2.2, height: 2.2)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
    }
}

struct DiscoverEmptyStateView: View {
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

