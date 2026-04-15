import SwiftUI

// MARK: - Search Sheet View

enum SearchPresentationStyle {
    case sheet
    case embedded
    case fullScreen
}

struct SearchSheetView: View {
    @Binding var isPresented: Bool
    @State private var searchQuery = ""
    @State private var searchResults: [SimpleWord] = []
    @State private var debounceTask: Task<Void, Never>?
    @State private var selectedWordForCard: SimpleWord?
    @FocusState private var isSearchFieldFocused: Bool
    @AppStorage("search_recent_word_ids") private var recentWordIDsStorage: String = ""
    
    private let wordById: [String: SimpleWord]
    private let searchIndex: WordSearchIndex
    let presentationStyle: SearchPresentationStyle
    var onWordSelected: ((SimpleWord) -> Void)?
    
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var srsManager: SRSManager
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    private var isLightAppearance: Bool {
        AppColors.usesLightAppearance(themeMode: appState.themeMode, isDarkMode: isDark)
    }
    private var normalizedQuery: String {
        normalizeSearchText(searchQuery)
    }
    private var resultsListHeight: CGFloat {
        presentationStyle == .sheet ? 240 : 320
    }
    private var emptyStateHeight: CGFloat {
        presentationStyle == .sheet ? 124 : 150
    }
    private var fullScreenBackground: LinearGradient {
        AppColors.appBackgroundGradient(themeMode: appState.themeMode, isDarkMode: isDark)
    }
    private var fullScreenControlHeight: CGFloat {
        52
    }
    private var fullScreenControlMaterial: Material {
        isDark ? .ultraThinMaterial : .regularMaterial
    }
    private var fullScreenControlFill: Color {
        if isLightAppearance { return AppColors.lightCard }
        return isDark ? AppColors.nocturneSurface.opacity(0.74) : Color.white.opacity(0.40)
    }
    private var fullScreenControlBorder: Color {
        if isLightAppearance { return Color.black.opacity(0.08) }
        return isDark ? AppColors.nocturneBorder : Color.white.opacity(0.88)
    }
    private var fullScreenControlInnerBorder: Color {
        if isLightAppearance { return Color.black.opacity(0.04) }
        return isDark ? AppColors.nocturneBorderSoft : Color.white.opacity(0.52)
    }
    private let maxRecentWordCount = 40
    
    init(
        isPresented: Binding<Bool>,
        allWords: [SimpleWord],
        conjugationMap: [String: String] = [:],
        searchIndex: WordSearchIndex? = nil,
        presentationStyle: SearchPresentationStyle = .sheet,
        onWordSelected: ((SimpleWord) -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.presentationStyle = presentationStyle
        self.wordById = Dictionary(uniqueKeysWithValues: allWords.map { ($0.id, $0) })
        self.searchIndex = searchIndex ?? WordSearchIndex.build(words: allWords, conjugationMap: conjugationMap)
        self.onWordSelected = onWordSelected
    }
    
    var body: some View {
        Group {
            if presentationStyle == .sheet {
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        // 背景半透明层
                        Color.clear
                            .contentShape(Rectangle())
                            .ignoresSafeArea()
                            .onTapGesture {
                                isPresented = false
                            }

                        // 搜索卡片（固定锚定到底部）
                        searchCard
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.bottom, max(16, geometry.safeAreaInsets.bottom + 78))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            } else if presentationStyle == .fullScreen {
                fullScreenSearchView
            } else {
                VStack(spacing: 0) {
                    searchCard
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isSearchFieldFocused = true
            }
        }
        .onChange(of: searchQuery) { _, newValue in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    performSearch(for: newValue)
                }
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            debounceTask = nil
        }
        #if os(iOS)
        .fullScreenCover(item: $selectedWordForCard) { word in
            SearchSelectedWordCardView(
                word: word,
                themeMode: appState.themeMode,
                allowsBlurrySwipe: true,
                dismissOnTap: true,
                onDismiss: { selectedWordForCard = nil },
                onSwipeForgot: { srsManager.markWordForgot($0, persistDuringInfinitePractice: true) },
                onSwipeMastered: { srsManager.markWordMastered($0, persistDuringInfinitePractice: true) },
                onSwipeBlurry: { srsManager.markWordBlurry($0, persistDuringInfinitePractice: true) }
            )
        }
        #else
        .sheet(item: $selectedWordForCard) { word in
            SearchSelectedWordCardView(
                word: word,
                themeMode: appState.themeMode,
                allowsBlurrySwipe: true,
                dismissOnTap: true,
                onDismiss: { selectedWordForCard = nil },
                onSwipeForgot: { srsManager.markWordForgot($0, persistDuringInfinitePractice: true) },
                onSwipeMastered: { srsManager.markWordMastered($0, persistDuringInfinitePractice: true) },
                onSwipeBlurry: { srsManager.markWordBlurry($0, persistDuringInfinitePractice: true) }
            )
        }
        #endif
    }
    
    private var searchCard: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack(spacing: 10) {
                searchTextField
                pasteFromClipboardButton
            }
            .padding(12)
            
            // 搜索结果或提示
            if normalizedQuery.isEmpty {
                emptyStateView
            } else if searchResults.isEmpty {
                noResultsView
            } else {
                resultsListView
            }
        }
        .background(backgroundCard)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 6)
    }

    private var fullScreenSearchView: some View {
        GeometryReader { _ in
            ZStack {
                ThemedBackgroundView(
                    themeMode: appState.themeMode,
                    isDarkMode: isDark
                )
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    fullScreenContent
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 6)
                        .padding(.horizontal, 20)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                fullScreenSearchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
        }
    }

    private var fullScreenSearchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(isDark ? .white.opacity(0.68) : .black.opacity(0.52))
                    .font(.system(size: 18, weight: .regular))

                TextField(appState.localized("Search words", "搜索单词", "शब्द खोजें"), text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .regular, design: .default))
                    .foregroundColor(isDark ? .white : .black)
                    .submitLabel(.search)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        debounceTask?.cancel()
                        performSearch(for: searchQuery)
                    }
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    #endif
            }
            .padding(.horizontal, 16)
            .frame(height: fullScreenControlHeight)
            .background(
                Capsule(style: .continuous)
                    .themedGlassSurface(themeMode: appState.themeMode, isDarkMode: isDark, elevated: true)
            )

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isDark ? Color.white.opacity(0.86) : Color.black.opacity(0.78))
                    .frame(width: fullScreenControlHeight, height: fullScreenControlHeight)
                    .background(
                        Circle()
                            .themedGlassSurface(themeMode: appState.themeMode, isDarkMode: isDark, elevated: true)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var fullScreenContent: some View {
        Group {
            if normalizedQuery.isEmpty {
                if recentWords.isEmpty {
                    emptyStateView
                } else {
                    wordListView(recentWords)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if searchResults.isEmpty {
                noResultsView
            } else {
                wordListView(searchResults)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private var searchTextField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.5))
                .font(.system(size: 16))
            
            TextField(appState.localized("Search words", "搜索单词", "शब्द खोजें"), text: $searchQuery)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 16))
                .foregroundColor(isDark ? .white : .black)
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    debounceTask?.cancel()
                    performSearch(for: searchQuery)
                }
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                #endif
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .themedGlassSurface(themeMode: appState.themeMode, isDarkMode: isDark, elevated: true)
        )
    }
    
    private var pasteFromClipboardButton: some View {
        Button(action: pasteFromClipboard) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 16))
                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.6))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .themedGlassSurface(themeMode: appState.themeMode, isDarkMode: isDark, elevated: true)
                )
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(isDark ? AppColors.nocturneTextTertiary : .black.opacity(0.3))
            
            Text(appState.localized("Type keywords to search local words", "输入关键词搜索本地单词列表", "स्थानीय शब्द खोजने के लिए कीवर्ड दर्ज करें"))
                .font(.system(size: 13))
                .foregroundColor(isDark ? AppColors.nocturneTextSecondary : .black.opacity(0.4))
        }
        .frame(height: emptyStateHeight)
        .padding(.vertical, 24)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 32))
                .foregroundColor(isDark ? AppColors.nocturneTextTertiary : .black.opacity(0.3))
            
            Text(appState.localized("No results found", "未找到结果", "कोई परिणाम नहीं मिला"))
                .font(.system(size: 13))
                .foregroundColor(isDark ? AppColors.nocturneTextSecondary : .black.opacity(0.4))
        }
        .frame(height: emptyStateHeight)
        .padding(.vertical, 24)
    }
    
    private var resultsListView: some View {
        wordListView(searchResults)
            .frame(height: resultsListHeight)
    }

    private func wordListView(_ words: [SimpleWord]) -> some View {
        List {
            ForEach(words) { word in
                wordResultRow(word)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
    
    private var recentWordIDs: [String] {
        recentWordIDsStorage
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var recentWords: [SimpleWord] {
        guard !wordById.isEmpty else { return [] }
        return recentWordIDs.compactMap { wordById[$0] }
    }

    private func addToRecentWords(_ word: SimpleWord) {
        var ids = recentWordIDs
        ids.removeAll { $0 == word.id }
        ids.insert(word.id, at: 0)
        if ids.count > maxRecentWordCount {
            ids = Array(ids.prefix(maxRecentWordCount))
        }
        recentWordIDsStorage = ids.joined(separator: ",")
    }

    private func wordResultRow(_ word: SimpleWord) -> some View {
        Button(action: {
            addToRecentWords(word)
            selectedWordForCard = word
            onWordSelected?(word)
        }) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(word.word)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(isDark ? AppColors.nocturneTextPrimary : Color.black.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(2)

                Text(appState.translationText(for: word))
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(isDark ? AppColors.nocturneTextSecondary : Color.black.opacity(0.44))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 205, alignment: .trailing)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.20)) {
                    srsManager.resetWordToNew(word.id)
                }
            } label: {
                Label(appState.localized("Delete", "删除", "हटाएं"), systemImage: "trash")
            }
            .tint(.red)
        }
    }
    
    private var backgroundCard: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .themedGlassSurface(themeMode: appState.themeMode, isDarkMode: isDark, elevated: true)
    }
    
    // MARK: - 辅助函数
    
    private func performSearch(for rawQuery: String) {
        searchResults = searchIndex.searchResults(for: rawQuery)
    }
    
    private func pasteFromClipboard() {
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        if let text = pasteboard.string {
            searchQuery = text
        }
        #endif
    }

    private func normalizeSearchText(_ text: String) -> String {
        SearchTextNormalizer.normalize(text)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var isPresented = true
        
        var body: some View {
            ZStack {
                Color.gray.opacity(0.2)
                    .ignoresSafeArea()
                
                Button("显示搜索") {
                    isPresented = true
                }
            }
            .sheet(isPresented: $isPresented) {
                SearchSheetView(
                    isPresented: $isPresented,
                    allWords: [
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
                        )
                    ]
                )
            }
        }
    }
    
    return PreviewWrapper()
}
