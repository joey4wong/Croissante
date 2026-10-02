import SwiftUI
import StoreKit
#if os(iOS)
import UIKit
#endif

struct SettingsScreen: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var appIconManager = AppIconManager.shared
    @State private var showingAvatarPicker = false
    @State private var showingFAQ = false
    @State private var showingTermsOfUse = false
    @State private var showingShareSheet = false
    @State private var showingAppIconPicker = false
    @State private var appIconErrorMessage: String?
    @State private var showingAppIconError = false
    @State private var showingResetLearningDataAlert = false
    @State private var themeSelectionOverride: Int?
    @State private var themeApplyTask: Task<Void, Never>?
    #if os(iOS)
    @State private var avatarImage: UIImage?
    @State private var avatarLoadTask: Task<Void, Never>?
    #endif

    private let languageCodes = ["en", "zh"]
    private var languages: [String] { ["English", "中文"] }
    private let appIconTileSize: CGFloat = 68
    private let developerContactEmail = "joey4wong@gmail.com"
    private let xProfileURL = "https://x.com/croissante4u?s=21"
    private let termsOfUseURL = "https://joey4wong.github.io/Croissante/terms.html"
    private let privacyPolicyURL = "https://joey4wong.github.io/Croissante/privacy.html"
    private let cardFontOptions: [(style: CardFontStyle, label: String)] = [
        (.sfPro, "SF Pro"),
        (.sfRounded, "SF R"),
        (.avenirNext, "Avenir N"),
        (.newYork, "New York")
    ]
    private var appShareMessage: String {
        appState.localized("I am learning French with Croissante. Join me!", "我正在用 Croissante 学法语，一起来！")
    }
    private var themes: [String] {
        [
            appState.localized("System", "跟随系统"),
            appState.localized("Light", "浅色"),
            appState.localized("Dark", "深色")
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

    private var selectedLanguageIndex: Int {
        languageCodes.firstIndex(of: appState.language) ?? 0
    }

    private var selectedThemeIndex: Int {
        switch appState.themeMode {
        case .system: return 0
        case .light: return 1
        case .dark: return 2
        }
    }

    private var displayedThemeIndex: Int {
        themeSelectionOverride ?? selectedThemeIndex
    }

    private var selectedVoiceName: String {
        TTSVoice(rawValue: appState.selectedVoiceId)?.displayName ?? TTSVoice.default.displayName
    }
    private var selectedCardFontLabel: String {
        cardFontOptions.first(where: { $0.style == appState.cardFontStyle })?.label ?? cardFontOptions[0].label
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
    private var faqItems: [FAQItem] {
        [
            FAQItem(
                id: "add-words",
                question: appState.localized("How do I add words?", "怎么添加单词？"),
                answer: appState.localized(
                    "Tap the white plus in the middle of the galaxy, type a French word, and it becomes a card in your orbit. The galaxy holds your 22 most recent words; older ones are always available from Search.",
                    "点击银河中央的白色加号，输入一个法语单词，它就会变成你轨道上的一张卡片。银河只展示最近的 22 个词，更早的词随时可以在搜索里找到。"
                )
            ),
            FAQItem(
                id: "blank-cards",
                question: appState.localized("What are the blank white cards?", "空白的白卡片是什么？"),
                answer: appState.localized(
                    "They are empty slots. Each word you add fills one. When all 22 are filled, the newest word replaces the oldest in the orbit.",
                    "它们是空位。每添加一个词就会填满一张。22 张全部填满后，最新的词会把最早的词挤出轨道。"
                )
            ),
            FAQItem(
                id: "favorites",
                question: appState.localized("What does the graduation cap do?", "学位帽是做什么的？"),
                answer: appState.localized(
                    "Tap the graduation cap on a card to favorite it. All favorites appear on the Progress page.",
                    "点击卡片上的学位帽即可收藏。所有收藏的词都会出现在进度页。"
                )
            ),
            FAQItem(
                id: "heatmap",
                question: appState.localized("How does the heatmap work?", "热力图是怎么计算的？"),
                answer: appState.localized(
                    "Each square is one day. It counts how many times you added or opened a word that day: 1-2 is light green, 3-5 is green, 6 or more is deep green.",
                    "每个方块代表一天，记录当天你添加或打开单词的次数：1-2 次浅绿，3-5 次绿色，6 次及以上深绿。"
                )
            ),
            FAQItem(
                id: "edit",
                question: appState.localized("Can I edit a card?", "可以编辑卡片吗？"),
                answer: appState.localized(
                    "Yes. Swipe up on an open card to edit the translation and example sentences.",
                    "可以。在打开的卡片上向上滑动，即可编辑翻译和例句。"
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
                            .strokeBorder(
                                AngularGradient(colors: avatarMetalRingGradient, center: .center),
                                lineWidth: 4
                            )
                            .frame(width: 100, height: 100)
                            .overlay(
                                Circle()
                                    .trim(from: 0.08, to: 0.36)
                                    .stroke(
                                        avatarMetalHighlight,
                                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-20))
                                    .frame(width: 96, height: 96)
                            )
                        Circle()
                            .stroke(isDarkMode ? Color.white.opacity(0.22) : Color.white.opacity(0.6), lineWidth: 2)
                            .frame(width: 100, height: 100)
                    }
                }
                .buttonStyle(.plain)
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
                }
                .onChange(of: appState.avatarPath) { _, _ in
                    refreshAvatarImage()
                }
                .onDisappear {
                    cancelAvatarImageLoading()
                }

                SettingsGroupCard {
                        SettingsCardRow(
                            icon: "waveform",
                            title: appState.localized("Natural Voice", "自然语音"),
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
                                ForEach(TTSVoice.allCases) { voice in
                                    Text(voice.displayName).tag(voice.rawValue)
                                }
                            }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .pickerStyle(.menu)
                            .tint(isDarkMode ? Color.white.opacity(0.52) : Color.black.opacity(0.44))
                            .frame(height: settingsMenuControlHeight, alignment: .center)
                        }
                }
                .padding(.horizontal, 20)

                SettingsGroupCard {
                        SettingsCardRow(
                            icon: "globe",
                            title: appState.localized("Language", "语言"),
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
                            title: appState.localized("Theme", "主题"),
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
                                        default: newMode = .system
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
                            title: appState.localized("Card Font", "卡片字体"),
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
                            icon: "icloud",
                            title: appState.localized("iCloud Sync", "iCloud 同步"),
                            subtitle: appState.localized("Sync learning progress across your devices", "在你的设备间同步学习进度"),
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
                            title: appState.localized("Auto-play", "自动播放"),
                            subtitle: appState.localized("Speak the word automatically", "自动朗读单词"),
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
                                title: appState.localized("Reset Data", "重置数据"),
                                subtitle: appState.localized("Delete all words", "删除所有单词"),
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
                        Button {
                            showingFAQ = true
                        } label: {
                            SettingsCardRow(
                                icon: "questionmark.circle",
                                title: appState.localized("FAQ", "常见问题"),
                                subtitle: appState.localized("Frequently asked questions", "常见问题解答"),
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
                                title: appState.localized("Terms of Use", "使用条款"),
                                subtitle: appState.localized("Terms and conditions", "条款与条件"),
                                titleFontSize: 13,
                                rowVerticalPadding: settingsOptionRowVerticalPadding,
                                showsDivider: true,
                                matchPickerFont: true
                            ) {
                                Image(systemName: "arrow.up.right")
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
                                title: appState.localized("Privacy Policy", "隐私政策"),
                                subtitle: appState.localized("How we handle your data", "我们如何处理你的数据"),
                                titleFontSize: 13,
                                rowVerticalPadding: settingsOptionRowVerticalPadding,
                                showsDivider: false,
                                matchPickerFont: true
                            ) {
                                Image(systemName: "arrow.up.right")
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
                            subtitle: appState.localized("One croissant a day, one French word away", "可颂天天有，法语天天懂。"),
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
                                "SF:square.and.arrow.up.circle.fill"
                            ],
                            accessibilityLabels: [
                                appState.localized("Report", "报错"),
                                "X",
                                appState.localized("Rate", "评分"),
                                appState.localized("Share", "分享")
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
                title: appState.localized("Terms of Use", "使用条款"),
                subtitle: appState.localized("Please review these terms before using the app.", "使用应用前，请先阅读以下条款。"),
                paragraphs: [
                    appState.localized("Croissante is designed for personal language learning. You are responsible for how you use the content and learning suggestions in your own study routine.", "Croissante 用于个人语言学习。你需要根据自己的学习情况判断并使用应用中的内容与学习建议。"),
                    appState.localized("Features and wording may evolve over time as the learning model improves. Continued use means you agree with these product updates.", "随着学习模型持续优化，功能和文案可能会调整。继续使用即表示你接受这些产品更新。"),
                    appState.localized("If you have questions about account behavior, progress data, or feature access, please contact support from the developer section.", "如对账户行为、学习进度数据或功能访问有疑问，请通过开发者页面的联系方式与我们沟通。")
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
            appState.localized("Unable to Change Icon", "图标切换失败"),
            isPresented: $showingAppIconError
        ) {
            Button(appState.localized("OK", "好的"), role: .cancel) {}
        } message: {
            Text(appIconErrorMessage ?? appState.localized("Please try again later.", "请稍后再试。"))
        }
        .alert(
            appState.localized("Reset Data", "重置数据"),
            isPresented: $showingResetLearningDataAlert
        ) {
            Button(appState.localized("Cancel", "取消"), role: .cancel) {}
            Button(appState.localized("Reset", "重置"), role: .destructive) {
                resetLearningData()
            }
        } message: {
            Text(
                appState.localized("This will delete all your words, favorites, activity history, recent searches, and cached audio. This cannot be undone.", "这会删除你添加的所有单词、收藏、活动记录、最近搜索和语音缓存。此操作无法撤销。")
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
                value: appState.localized("Croissante Feedback", "Croissante 反馈")
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
        appState.resetLibrary()
        favoritesStore.removeAll()
        AudioCacheManager.shared.clearCache()
        UserDefaults.standard.removeObject(forKey: "search_recent_word_ids")
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
            showingAppIconPicker = true
        } label: {
            SettingsCardRow(
                icon: "swirl.circle.righthalf.filled",
                iconAssetName: "croissante_dev_icon",
                title: appState.localized("App Icon", "应用图标"),
                subtitle: "",
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

    private var appIconPickerSheet: some View {
        Group {
            #if os(iOS)
            AppIconPhysicsPicker(
                icons: AppIconManager.AppIcon.allIcons,
                currentIconID: appIconManager.currentIcon.id,
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
        showingAppIconPicker = false
        applyAppIcon(icon)
    }

    private func appIconTile(_ icon: AppIconManager.AppIcon) -> some View {
        let isSelected = appIconManager.currentIcon.id == icon.id
        let isLocked = false
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
