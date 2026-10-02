import SwiftUI

struct HomeScreen: View {
    let isActiveTab: Bool

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var presentedRequest: GalaxySelectedCardTransitionRequest? = nil
    @State private var cardPhase: ActiveCardHost.Phase = .entering
    @State private var galaxyReturnToken = 0
    @State private var flyInWordId: String? = nil
    @State private var flyInResetTask: Task<Void, Never>? = nil

    private let slotCount = 22

    private var isDarkMode: Bool { colorScheme == .dark }

    private var slots: [GalaxySlot] {
        let visibleWords = Array(appState.words.prefix(slotCount))
        var result = visibleWords.map { GalaxySlot(id: $0.id, word: $0) }
        var blankIndex = 0
        while result.count < slotCount {
            result.append(GalaxySlot(id: "blank-\(blankIndex)", word: nil))
            blankIndex += 1
        }
        return result
    }

    private var presentedWord: SimpleWord? {
        guard let request = presentedRequest else { return nil }
        return appState.getWordById(request.word.id) ?? request.word
    }

    var body: some View {
        ZStack {
            ThemedBackgroundView(themeMode: appState.themeMode, isDarkMode: isDarkMode)

            GeometryReader { geo in
                ZStack {
                    WordGalaxyView(
                        slots: slots,
                        flyInWordId: flyInWordId,
                        returnToken: galaxyReturnToken,
                        isInteractive: presentedRequest == nil && isActiveTab,
                        onSelectCard: beginPresenting
                    )
                    .frame(width: geo.size.width, height: geo.size.height)

                    if presentedRequest != nil, cardPhase == .presented {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: geo.size.width, height: geo.size.height)
                            .onTapGesture { beginDismissing() }
                    }

                    if let request = presentedRequest, let word = presentedWord {
                        ActiveCardHost(
                            word: word,
                            transitionRequest: request,
                            phase: cardPhase,
                            containerSize: geo.size,
                            isActiveTab: isActiveTab,
                            onEnterComplete: { cardPhase = .presented },
                            onLeaveComplete: finishDismissing
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onChange(of: isActiveTab) { _, active in
            guard !active, presentedRequest != nil else { return }
            finishDismissing()
        }
        .onChange(of: appState.words.map(\.id)) { oldIds, ids in
            if let request = presentedRequest, !ids.contains(request.word.id) {
                finishDismissing()
            }
            let previous = Set(oldIds)
            if let added = ids.first(where: { !previous.contains($0) }) {
                flyIn(wordId: added)
            }
        }
    }

    private func beginPresenting(_ request: GalaxySelectedCardTransitionRequest) {
        guard presentedRequest == nil else { return }
        cardPhase = .entering
        presentedRequest = request
        appState.recordLookup(wordId: request.word.id)
    }

    private func beginDismissing() {
        guard presentedRequest != nil, cardPhase == .presented else { return }
        cardPhase = .leaving
        galaxyReturnToken += 1
    }

    private func finishDismissing() {
        if cardPhase != .leaving {
            galaxyReturnToken += 1
        }
        presentedRequest = nil
        cardPhase = .entering
    }

    private func flyIn(wordId: String) {
        flyInResetTask?.cancel()
        flyInWordId = nil
        DispatchQueue.main.async {
            flyInWordId = wordId
        }
        flyInResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            flyInWordId = nil
        }
    }
}
