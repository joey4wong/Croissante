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
    @State private var isAddSheetPresented = false

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
                        onSelectCard: beginPresenting,
                        onAddTapped: { isAddSheetPresented = true }
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
        .sheet(isPresented: $isAddSheetPresented) {
            AddWordSheet { form in
                addWord(form)
            }
            .environmentObject(appState)
            .presentationDetents([.height(196)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
        }
        .onChange(of: isActiveTab) { _, active in
            guard !active, presentedRequest != nil else { return }
            finishDismissing()
        }
        .onChange(of: appState.words.map(\.id)) { _, ids in
            guard let request = presentedRequest, !ids.contains(request.word.id) else { return }
            finishDismissing()
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

    private func addWord(_ form: String) {
        guard let word = appState.addWord(form: form) else { return }
        FeedbackService.wordAdded()
        flyInResetTask?.cancel()
        flyInWordId = nil
        DispatchQueue.main.async {
            flyInWordId = word.id
        }
        flyInResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            flyInWordId = nil
        }
    }
}

struct AddWordSheet: View {
    let onSubmit: (String) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var isDarkMode: Bool { colorScheme == .dark }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            ThemedBackgroundView(themeMode: appState.themeMode, isDarkMode: isDarkMode)
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text(appState.localized("Add a French word", "添加一个法语单词"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.56) : Color.black.opacity(0.46))
                    .padding(.leading, 6)

                HStack(spacing: 10) {
                    TextField(appState.localized("bonjour", "bonjour"), text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(isDarkMode ? Color.white : Color.black.opacity(0.88))
                        .submitLabel(.done)
                        .focused($isFocused)
                        .onSubmit(submit)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.default)
                        #endif
                        .padding(.horizontal, 18)
                        .frame(height: 56)
                        .background(
                            Capsule(style: .continuous)
                                .themedGlassSurface(themeMode: appState.themeMode, isDarkMode: isDarkMode, elevated: true)
                        )

                    Button(action: submit) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.62))
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(isDarkMode ? 0.40 : 0.12), radius: 12, x: 0, y: 6)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmed.isEmpty)
                    .opacity(trimmed.isEmpty ? 0.45 : 1)
                    .animation(.easeOut(duration: 0.16), value: trimmed.isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                isFocused = true
            }
        }
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        dismiss()
    }
}
