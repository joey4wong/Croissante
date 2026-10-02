import SwiftUI
import Combine
import AVFoundation
#if os(iOS)
import UIKit
import CoreMotion
#endif

struct SearchSelectedWordCardView: View {
    let word: SimpleWord
    let themeMode: ThemeMode
    let dismissOnTap: Bool
    let onDismiss: () -> Void

    init(
        word: SimpleWord,
        themeMode: ThemeMode = .system,
        dismissOnTap: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self.word = word
        self.themeMode = themeMode
        self.dismissOnTap = dismissOnTap
        self.onDismiss = onDismiss
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var isCardInlineEditing = false

    var body: some View {
        GeometryReader { geo in
            let contentWidth = DiscoverCardLayout.contentWidth(forScreenWidth: geo.size.width)
            let cardHeight = DiscoverCardLayout.cardHeight(forCardWidth: contentWidth)
            let containerHeight = geo.size.height
            let restingCardYOffset = DiscoverCardLayout.restingCardYOffset(containerHeight: containerHeight)
            let editingDockingOffset = isCardInlineEditing
                ? DiscoverCardLayout.keyboardDockingOffset(
                    containerHeight: containerHeight,
                    cardContentHeight: cardHeight,
                    restingYOffset: restingCardYOffset
                )
                : 0
            let cardYOffset = restingCardYOffset + editingDockingOffset
            ZStack {
                if dismissOnTap {
                    ThemedBackgroundView(
                        themeMode: themeMode,
                        isDarkMode: colorScheme == .dark
                    )
                        .contentShape(Rectangle())
                        .onTapGesture { onDismiss() }
                } else {
                    ThemedBackgroundView(
                        themeMode: themeMode,
                        isDarkMode: colorScheme == .dark
                    )
                }

                DiscoverCard(
                    word: word,
                    screenWidth: contentWidth,
                    screenHeight: containerHeight,
                    cardWidth: contentWidth,
                    cardHeight: cardHeight,
                    isActiveTab: true,
                    allowsInlineEditing: true,
                    audioReactiveDividerEnabled: true,
                    usesHomeSurfaceStyle: true,
                    onInlineEditingChange: { editing in
                        withAnimation(.easeOut(duration: editing ? 0.22 : 0.16)) {
                            isCardInlineEditing = editing
                        }
                    }
                )
                .id(word.id)
                .frame(width: contentWidth, height: containerHeight)
                .position(x: geo.size.width / 2, y: containerHeight / 2 + cardYOffset)
            }
        }
        .onChange(of: word.id) { _, _ in
            isCardInlineEditing = false
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .interactiveDismissDisabled()
        #if os(iOS)
        .ignoresSafeArea(.container, edges: .bottom)
        #endif
    }
}

enum LocalizedCardEditField: Hashable {
    case translation
    case frenchExample
    case example
}

struct DiscoverCard: View {
    let word: SimpleWord
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let cardWidth: CGFloat?
    let cardHeight: CGFloat?
    let isActiveTab: Bool
    let detailProgress: Double
    let contentOpacity: Double
    let interactionsEnabled: Bool
    let allowsInlineEditing: Bool
    let audioReactiveDividerEnabled: Bool
    let usesHomeSurfaceStyle: Bool
    let onInlineEditingChange: ((Bool) -> Void)?
    let showsBottomMetaBar: Bool

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOffset: CGSize = .zero
    @State private var dragRotation: Angle = .zero
    @State private var editLandingSpinDegrees: Double = 0
    @State private var isInlineEditFlightActive = false
    @State private var isSwipeCompleting = false
    @State private var dragLockedAxis: Axis? = nil
    @State private var swipeOutOpacity: Double = 1.0
    @State private var swipeOutBlur: CGFloat = 0
    private let arcMaxHeight: CGFloat = 32
    @State private var pendingSpeechTask: Task<Void, Never>?
    @State private var displayedWord: SimpleWord
    @State private var isEditingLocalizedContent = false
    @State private var localizedTranslationDraft = ""
    @State private var localizedFrenchExampleDraft = ""
    @State private var localizedExampleDraft = ""
    @FocusState private var focusedEditField: LocalizedCardEditField?

    init(
        word: SimpleWord,
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        cardWidth: CGFloat? = nil,
        cardHeight: CGFloat? = nil,
        isActiveTab: Bool,
        detailProgress: Double = 1,
        contentOpacity: Double = 1,
        interactionsEnabled: Bool = true,
        allowsInlineEditing: Bool = false,
        audioReactiveDividerEnabled: Bool = false,
        usesHomeSurfaceStyle: Bool = false,
        onInlineEditingChange: ((Bool) -> Void)? = nil,
        showsBottomMetaBar: Bool = true
    ) {
        self.word = word
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.isActiveTab = isActiveTab
        self.detailProgress = detailProgress
        self.contentOpacity = contentOpacity
        self.interactionsEnabled = interactionsEnabled
        self.allowsInlineEditing = allowsInlineEditing
        self.audioReactiveDividerEnabled = audioReactiveDividerEnabled
        self.usesHomeSurfaceStyle = usesHomeSurfaceStyle
        self.onInlineEditingChange = onInlineEditingChange
        self.showsBottomMetaBar = showsBottomMetaBar
        _displayedWord = State(initialValue: word)
    }

    private let swipeThreshold: CGFloat = 100
    private var resolvedCardWidth: CGFloat {
        max(cardWidth ?? screenWidth, 0)
    }
    private var resolvedCardHeight: CGFloat {
        max(cardHeight ?? DiscoverCardLayout.cardHeight(forCardWidth: resolvedCardWidth), 0)
    }
    private var supportsUpwardAction: Bool {
        allowsInlineEditing
    }
    private var upwardFlyOutOffset: CGSize {
        CGSize(
            width: 0,
            height: -max(screenHeight * 0.92, resolvedCardHeight + 280)
        )
    }
    private var isDarkMode: Bool { colorScheme == .dark }
    private var secondaryTextColor: Color {
        isDarkMode ? AppColors.nocturneTextSecondary : Color.black.opacity(0.42)
    }

    private var bottomMetaReveal: Double {
        galaxySmoothStep((detailProgress - 0.10) / 0.72)
    }

    private func speakWord() {
        let trimmedWord = displayedWord.displayWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }
        
        ElevenLabsTTSService.stopPlayback()
        ElevenLabsTTSService.speakText(
            trimmedWord,
            language: "fr-FR",
            contentType: .word,
            playbackID: audioReactiveDividerEnabled ? displayedWord.id : nil
        )
    }

    private func speakExampleSentence() {
        let trimmedExample = appState.frenchExampleText(for: displayedWord)
        guard !trimmedExample.isEmpty else { return }

        ElevenLabsTTSService.stopPlayback()
        ElevenLabsTTSService.speakText(
            trimmedExample,
            language: "fr-FR",
            contentType: .sentence,
            playbackID: audioReactiveDividerEnabled ? displayedWord.id : nil
        )
    }

    private func cancelScheduledSpeech() {
        pendingSpeechTask?.cancel()
        pendingSpeechTask = nil
    }

    private func stopSpeechPlayback() {
        cancelScheduledSpeech()
        ElevenLabsTTSService.stopPlayback()
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

    private func loadLocalizedEditDrafts(for word: SimpleWord) {
        let content = appState.editableLocalizedContent(for: word)
        localizedTranslationDraft = content.translation
        localizedFrenchExampleDraft = content.frenchExample
        localizedExampleDraft = content.example
    }

    private func saveLocalizedEditDrafts() {
        guard isEditingLocalizedContent else { return }
        appState.saveLocalizedContent(
            UserWordLocalizedContent(
                translation: localizedTranslationDraft,
                frenchExample: localizedFrenchExampleDraft,
                example: localizedExampleDraft
            ),
            for: displayedWord
        )
        if let updated = appState.getWordById(displayedWord.id) {
            displayedWord = updated
        }
    }

    private func beginInlineEditing() {
        guard allowsInlineEditing, !isEditingLocalizedContent else { return }
        stopSpeechPlayback()
        loadLocalizedEditDrafts(for: displayedWord)
        isSwipeCompleting = true
        isInlineEditFlightActive = true
        dragLockedAxis = nil

        let editingWordId = displayedWord.id
        let flyOutOffset = upwardFlyOutOffset
        let flyOutDuration: TimeInterval = 0.18
        let editHandoffDelay: TimeInterval = 0.18
        let keyboardSettleDelay: TimeInterval = 0.02
        let landingDuration: TimeInterval = 1.05
        let landingAnimation = Animation.timingCurve(0.08, 0.92, 0.14, 1.0, duration: landingDuration)
        let landingSpinDegrees = 360.0 * 18
        editLandingSpinDegrees = 0

        withAnimation(.easeIn(duration: flyOutDuration)) {
            dragOffset = flyOutOffset
            dragRotation = .zero
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + editHandoffDelay) {
            guard displayedWord.id == editingWordId, isActiveTab else {
                isSwipeCompleting = false
                isInlineEditFlightActive = false
                return
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = flyOutOffset
                dragRotation = .zero
                editLandingSpinDegrees = 0
                isEditingLocalizedContent = true
            }
            onInlineEditingChange?(true)

            focusedEditField = .translation

            DispatchQueue.main.asyncAfter(deadline: .now() + keyboardSettleDelay) {
                guard displayedWord.id == editingWordId else {
                    isSwipeCompleting = false
                    isInlineEditFlightActive = false
                    return
                }

                withAnimation(landingAnimation) {
                    dragOffset = .zero
                }
                withAnimation(landingAnimation) {
                    editLandingSpinDegrees = landingSpinDegrees
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + landingDuration + 0.02) {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        editLandingSpinDegrees = 0
                    }
                    dragRotation = .zero
                    dragOffset = .zero
                    swipeOutOpacity = 1
                    swipeOutBlur = 0
                    isSwipeCompleting = false
                    isInlineEditFlightActive = false
                }
            }
        }
    }

    private func finishInlineEditing() {
        guard isEditingLocalizedContent else { return }
        saveLocalizedEditDrafts()
        onInlineEditingChange?(false)
        withAnimation(.easeOut(duration: 0.16)) {
            isEditingLocalizedContent = false
        }
        focusedEditField = nil
    }

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                CardBody(
                    word: displayedWord,
                    cardWidth: cardWidth ?? 0,
                    cardHeight: cardHeight ?? 0,
                    detailProgress: detailProgress,
                    contentOpacity: contentOpacity,
                    audioReactiveDividerEnabled: audioReactiveDividerEnabled,
                    usesHomeSurfaceStyle: usesHomeSurfaceStyle,
                    isEditingLocalizedContent: isEditingLocalizedContent,
                    localizedTranslationDraft: $localizedTranslationDraft,
                    localizedFrenchExampleDraft: $localizedFrenchExampleDraft,
                    localizedExampleDraft: $localizedExampleDraft,
                    focusedEditField: $focusedEditField,
                    onEditSubmit: finishInlineEditing,
                    onTitleTap: isEditingLocalizedContent ? nil : { [self] in cancelScheduledSpeech(); speakWord() },
                    onDetailTap: isEditingLocalizedContent ? nil : { [self] in cancelScheduledSpeech(); speakExampleSentence() }
                )
                    .overlay(alignment: .bottomLeading) {
                        if showsBottomMetaBar {
                            favoriteToggleButton
                                .padding(.leading, 12)
                                .padding(.bottom, 12)
                                .opacity(bottomMetaReveal)
                        }
                    }
            }
            .rotationEffect(dragRotation)
            .offset(dragOffset)
            .rotation3DEffect(
                .degrees(editLandingSpinDegrees),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.55
            )
            .opacity(swipeOutOpacity)
            .blur(radius: swipeOutBlur)
            .allowsHitTesting(interactionsEnabled)
            .gesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { v in
                        guard interactionsEnabled, !isSwipeCompleting, !isEditingLocalizedContent else { return }
                        let dx = v.translation.width
                        let dy = v.translation.height
                        if dragLockedAxis == nil {
                            let mag = hypot(dx, dy)
                            if mag > 8 {
                                dragLockedAxis = abs(dx) > abs(dy) ? .horizontal : .vertical
                            }
                        }
                        let constrained: CGSize
                        switch dragLockedAxis {
                        case .horizontal:
                            constrained = .zero
                            dragRotation = .zero
                        case .vertical:
                            constrained = CGSize(width: 0, height: min(0, dy) * 0.6)
                            dragRotation = .zero
                        case nil:
                            constrained = .zero
                            dragRotation = .zero
                        }
                        dragOffset = constrained
                    }
                    .onEnded { v in
                        guard interactionsEnabled, !isSwipeCompleting, !isEditingLocalizedContent else { return }
                        let locked = dragLockedAxis
                        dragLockedAxis = nil
                        let dy = locked == .horizontal ? 0 : v.translation.height
                        if dy < -swipeThreshold, supportsUpwardAction {
                            beginInlineEditing()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                dragOffset = .zero
                                dragRotation = .zero
                            }
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
                    finishInlineEditing()
                    stopSpeechPlayback()
                }
            }
            .onChange(of: appState.language) { _, _ in
                guard isEditingLocalizedContent else { return }
                loadLocalizedEditDrafts(for: displayedWord)
                DispatchQueue.main.async {
                    focusedEditField = .translation
                }
            }
            .onChange(of: focusedEditField) { _, newValue in
                if isEditingLocalizedContent && newValue == nil {
                    finishInlineEditing()
                }
            }
            .onChange(of: word.id) { _, _ in
                finishInlineEditing()
                displayedWord = word
                if interactionsEnabled && isActiveTab && appState.autoPlay {
                    scheduleAutoPlay()
                }
            }
            .onDisappear {
                finishInlineEditing()
                stopSpeechPlayback()
            }
            .onAppear {
                displayedWord = word
                if interactionsEnabled && isActiveTab && appState.autoPlay {
                    scheduleAutoPlay()
                }
            }
        }
    }

    @ViewBuilder
    private var favoriteToggleButton: some View {
        Image(systemName: favoritesStore.isFavorite(displayedWord.id) ? "graduationcap.fill" : "graduationcap")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(secondaryTextColor)
            .frame(minWidth: 28, minHeight: 28)
            .accessibilityLabel(appState.localized("Favorite", "收藏"))
            .background(capsuleGlassBackground(interactive: true, isDarkMode: isDarkMode))
            .contentShape(Capsule())
            .onTapGesture {
                guard interactionsEnabled else { return }
                FeedbackService.cardMetaButtonTap()
                favoritesStore.toggleFavorite(wordId: displayedWord.id)
            }
    }

}

@ViewBuilder
func capsuleGlassBackground(interactive: Bool, isDarkMode: Bool) -> some View {
    if #available(iOS 26.0, *) {
        let tint: Color = isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
        if interactive {
            Color.clear
                .glassEffect(.regular.tint(tint).interactive(), in: Capsule(style: .continuous))
        } else {
            Color.clear
                .glassEffect(.regular.tint(tint), in: Capsule(style: .continuous))
        }
    } else {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
    }
}

struct ConditionalBlur: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        if radius > 0 {
            content.blur(radius: radius)
        } else {
            content
        }
    }
}

struct OptionalTapModifier: ViewModifier {
    let action: (() -> Void)?
    func body(content: Content) -> some View {
        if let action {
            content.contentShape(Rectangle()).onTapGesture { action() }
        } else {
            content
        }
    }
}

@MainActor
struct DottedAudioDivider: View {
    let color: Color
    let playbackID: String?

    @ObservedObject private var ttsService = ElevenLabsTTSService.shared
    private let reactingColor = Color(red: 0.16, green: 0.82, blue: 0.48)

    private var isReacting: Bool {
        guard let playbackID else { return false }
        return ttsService.isPlaybackActive && ttsService.currentPlaybackID == playbackID
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                drawDots(in: size, at: timeline.date, context: &context)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawDots(in size: CGSize, at date: Date, context: inout GraphicsContext) {
        let dotSpacing: CGFloat = 6
        let baseDiameter: CGFloat = 2.1
        let width = max(size.width, 1)
        let count = max(2, Int(width / dotSpacing))
        let startX = (width - CGFloat(count - 1) * dotSpacing) / 2
        let centerY = size.height / 2
        let waveform = isReacting ? ttsService.playbackWaveform : []
        let hasWaveform = waveform.count > 2
        let playbackProgress = isReacting ? ttsService.playbackProgress : 0
        let level = isReacting ? max(0.08, min(1, ttsService.playbackLevel)) : 0
        let time = date.timeIntervalSinceReferenceDate
        let waveformSpan = hasWaveform
            ? min(1.0, max(0.38, Double(count) / Double(max(waveform.count, count))))
            : 1.0
        let waveformStart = min(max(0, playbackProgress - waveformSpan * 0.18), max(0, 1 - waveformSpan))

        for index in 0..<count {
            let dotProgress = count == 1 ? 0 : Double(index) / Double(count - 1)
            let edgeEnvelope = CGFloat(sin(dotProgress * Double.pi))
            let amplitudeValue: Double
            if hasWaveform {
                amplitudeValue = waveformValue(
                    at: waveformStart + dotProgress * waveformSpan,
                    samples: waveform
                )
            } else {
                amplitudeValue = level * (0.46 + 0.54 * abs(sin(time * 9.0 + Double(index) * 0.51)))
            }
            let amplitude = CGFloat(amplitudeValue)
            let centeredAmplitude = amplitude - (hasWaveform ? 0.34 : 0.30)
            let yOffset = isReacting
                ? -centeredAmplitude * (11.0 + CGFloat(level) * 3.2) * (0.34 + edgeEnvelope * 0.66)
                : 0
            let pulse = isReacting ? 1 + amplitude * 0.48 : 1
            let diameter = baseDiameter * pulse
            let x = startX + CGFloat(index) * dotSpacing
            let rect = CGRect(
                x: x - diameter / 2,
                y: centerY + yOffset - diameter / 2,
                width: diameter,
                height: diameter
            )
            let opacity = isReacting ? 0.54 + amplitudeValue * 0.40 : 1
            let dotColor = isReacting ? reactingColor : color
            context.fill(Path(ellipseIn: rect), with: .color(dotColor.opacity(opacity)))
        }
    }

    private func waveformValue(at progress: Double, samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        guard samples.count > 1 else { return samples[0] }

        let clampedProgress = min(1, max(0, progress))
        let scaledIndex = clampedProgress * Double(samples.count - 1)
        let lowerIndex = Int(floor(scaledIndex))
        let upperIndex = min(samples.count - 1, lowerIndex + 1)
        let fraction = scaledIndex - Double(lowerIndex)
        return samples[lowerIndex] * (1 - fraction) + samples[upperIndex] * fraction
    }
}

struct CardBody: View {
    let word: SimpleWord
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let detailProgress: Double
    var contentOpacity: Double = 1.0
    let audioReactiveDividerEnabled: Bool
    var usesHomeSurfaceStyle: Bool = false
    let isEditingLocalizedContent: Bool
    var localizedTranslationDraft: Binding<String>? = nil
    var localizedFrenchExampleDraft: Binding<String>? = nil
    var localizedExampleDraft: Binding<String>? = nil
    var focusedEditField: FocusState<LocalizedCardEditField?>.Binding? = nil
    var onEditSubmit: () -> Void = {}
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
    private var usesHomeLightSurface: Bool {
        usesHomeSurfaceStyle && AppColors.usesLightAppearance(themeMode: appState.themeMode, isDarkMode: isDarkMode)
    }

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
    private var editFieldFill: Color {
        isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.045)
    }
    private var homeCardSurfaceFill: Color {
        Color(red: 250.0 / 255.0, green: 250.0 / 255.0, blue: 250.0 / 255.0)
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
                .padding(.top, 12)
                .padding(.trailing, 12)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var levelAuxiliaryBadge: some View {
        if !word.auxiliary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            auxiliaryBadgeContent
        }
    }

    private var auxiliaryBadgeContent: some View {
        HStack(spacing: 6) {
            Text(word.auxiliary)
        }
        .font(cardFont(size: 10 * (2.0 / 3.0), weight: .medium))
        .tracking(0.7)
        .foregroundStyle(levelTextColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(capsuleGlassBackground(interactive: false, isDarkMode: isDarkMode))
    }

    private func layerOpacity(delay: Double) -> Double {
        guard contentOpacity < 1.0 else { return 1.0 }
        let t = min(1.0, max(0.0, (contentOpacity - delay) / max(0.01, 1.0 - delay)))
        return t * t * (3.0 - 2.0 * t)
    }

    @ViewBuilder
    private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if usesHomeLightSurface {
            shape
                .fill(homeCardSurfaceFill)
                .shadow(color: Color.black.opacity(0.055), radius: 26, x: 0, y: 12)
                .overlay {
                    shape.stroke(Color.black.opacity(0.065), lineWidth: 1)
                }
                .overlay {
                    shape.inset(by: 1)
                        .stroke(Color.white.opacity(0.72), lineWidth: 0.8)
                }
        } else {
            shape.themedGlassSurface(themeMode: appState.themeMode, isDarkMode: isDarkMode, elevated: true)
        }
    }

    @ViewBuilder
    private var cardDivider: some View {
        if audioReactiveDividerEnabled {
            ZStack {
                DottedAudioDivider(color: dividerColor, playbackID: word.id)
                    .frame(maxWidth: .infinity)
                    .frame(height: 18)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 1)
        } else {
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
        }
    }

    private func editableField(
        text: Binding<String>,
        field: LocalizedCardEditField,
        focusedEditField: FocusState<LocalizedCardEditField?>.Binding,
        fontSize: CGFloat,
        textColor: Color,
        minHeight: CGFloat,
        lineLimit: PartialRangeThrough<Int>
    ) -> some View {
        let measurementText = text.wrappedValue.isEmpty ? " " : text.wrappedValue

        return ZStack(alignment: .leading) {
            Text(measurementText)
                .font(cardFont(size: fontSize))
                .lineSpacing(3)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .opacity(0)
                .accessibilityHidden(true)

            TextField("", text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(cardFont(size: fontSize))
                .lineSpacing(3)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .submitLabel(.done)
                .focused(focusedEditField, equals: field)
                .foregroundStyle(textColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(editFieldFill)
            )
            .onChange(of: text.wrappedValue) { _, newValue in
                guard newValue.rangeOfCharacter(from: .newlines) != nil else { return }
                text.wrappedValue = newValue
                    .components(separatedBy: .newlines)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                onEditSubmit()
            }
            .onSubmit(onEditSubmit)
    }

    var body: some View {
        cardContent
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(width: cardWidth, alignment: .top)
            .overlay(alignment: .topLeading) {
                levelAuxiliaryBadge
                    .padding(.leading, 12)
                    .padding(.top, 12)
                    .opacity(primaryReveal * 0.78 * layerOpacity(delay: 0.00) * contentOpacity)
            }
            .overlay(alignment: .topTrailing) {
                nounCornerBadge
                    .opacity(primaryReveal * contentOpacity)
            }
            .background(
                cardSurface
            )
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.displayWord)
                    .font(cardFont(size: titleBaseFontSize, weight: .semibold))
                    .tracking(0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.42)
                    .allowsTightening(true)
                    .foregroundStyle(headlineTextColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 7)
                    .opacity(layerOpacity(delay: 0.26))
            }
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(OptionalTapModifier(action: onTitleTap))

            definitionBlock
                .padding(.bottom, 28)
                .modifier(OptionalTapModifier(action: onDetailTap))

            cardDivider
                .padding(.bottom, 28)
                .opacity((0.18 + primaryReveal * 0.82) * layerOpacity(delay: 0.60))

            exampleBlock
                .modifier(OptionalTapModifier(action: onDetailTap))
        }
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
    }

    private var definitionBlock: some View {
        Group {
            if isEditingLocalizedContent,
               let localizedTranslationDraft,
               let focusedEditField {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(posLabel(word.tag))
                        .font(cardFont(size: 16, weight: .medium))
                        .foregroundStyle(secondaryTextColor)

                    editableField(
                        text: localizedTranslationDraft,
                        field: .translation,
                        focusedEditField: focusedEditField,
                        fontSize: 16,
                        textColor: secondaryTextColor,
                        minHeight: 36,
                        lineLimit: ...3
                    )
                }
            } else {
                Text("\(posLabel(word.tag))  \(appState.translationText(for: word))")
                    .font(cardFont(size: 16, weight: .medium))
                    .lineSpacing(5)
                    .lineLimit(nil)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
        .opacity(primaryReveal * layerOpacity(delay: 0.46))
    }

    @ViewBuilder
    private var exampleBlock: some View {
        let frenchExample = appState.frenchExampleText(for: word)
        let translatedExample = appState.translatedExampleText(for: word)
        if isEditingLocalizedContent || !frenchExample.isEmpty || !translatedExample.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if isEditingLocalizedContent,
                   let localizedFrenchExampleDraft,
                   let focusedEditField {
                    editableField(
                        text: localizedFrenchExampleDraft,
                        field: .frenchExample,
                        focusedEditField: focusedEditField,
                        fontSize: 16,
                        textColor: exampleTextColor,
                        minHeight: 42,
                        lineLimit: ...4
                    )
                } else if !frenchExample.isEmpty {
                    Text(frenchExample)
                        .foregroundStyle(exampleTextColor)
                        .font(cardFont(size: 16))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if isEditingLocalizedContent,
                   let localizedExampleDraft,
                   let focusedEditField {
                    editableField(
                        text: localizedExampleDraft,
                        field: .example,
                        focusedEditField: focusedEditField,
                        fontSize: 15,
                        textColor: exampleTranslationColor,
                        minHeight: 42,
                        lineLimit: ...4
                    )
                } else if !translatedExample.isEmpty {
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
            .opacity(secondaryReveal * layerOpacity(delay: 0.76))
        }
    }
}

struct NounCornerAccentShape: Shape {
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

func posLabel(_ tag: String) -> String {
    switch tag.uppercased() {
    case "N":
        return "n."
    case "V":
        return "v."
    case "A":
        return "adj."
    case "ADV":
        return "adv."
    case "INTJ":
        return "intj."
    case "PREP":
        return "prep."
    case "CONJ":
        return "conj."
    case "PRON":
        return "pron."
    case "DET":
        return "det."
    case "ART":
        return "art."
    default:
        return tag
    }
}
