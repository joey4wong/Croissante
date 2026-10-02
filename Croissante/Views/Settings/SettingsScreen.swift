import SwiftUI
import StoreKit
import Combine
import AVFoundation
#if os(iOS)
import UIKit
import CoreMotion
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
                appState.localized("This will clear your learning progress, recent searches, edited card text, and private audio generated from edited text. It also restores the system theme and official word content. This cannot be undone.", "这会清空你的学习进度、最近搜索记录、你编辑过的卡牌文本，以及由编辑文本生成的本机私有语音缓存。同时会恢复系统主题和官方单词内容。此操作无法撤销。")
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

#if os(iOS)
struct AppIconPhysicsPicker: UIViewRepresentable {
    let icons: [AppIconManager.AppIcon]
    let currentIconID: String
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
                let isLocked = false
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

final class AppIconPhysicsContainerView: UIView {
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

final class AppIconPhysicsTileView: UIControl {
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

struct SettingsGroupCard<Content: View>: View {
    let content: Content
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var borderColor: Color {
        if AppColors.usesLightAppearance(themeMode: appState.themeMode, isDarkMode: colorScheme == .dark) {
            return Color.black.opacity(0.08)
        }
        return colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.07)
    }

    private var fillColor: Color {
        if AppColors.usesLightAppearance(themeMode: appState.themeMode, isDarkMode: colorScheme == .dark) {
            return AppColors.lightCard
        }
        return colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.95)
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .themedGlassSurface(themeMode: appState.themeMode, isDarkMode: colorScheme == .dark, elevated: true)
        )
    }
}

struct SettingsCardRow<Trailing: View>: View {
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

struct SettingsActionButtonsRow: View {
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
struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

