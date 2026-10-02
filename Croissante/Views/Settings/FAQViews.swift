import SwiftUI
import Combine
import AVFoundation
#if os(iOS)
import UIKit
import CoreMotion
#endif

struct FAQItem: Identifiable {
    let id: String
    let question: String
    let answer: String
}

struct FAQSheetView: View {
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
                        eyebrow: appState.localized("Learning FAQ", "学习机制 FAQ"),
                        title: appState.localized("Understand how Explore cards are selected, repeated, and truly completed.", "了解首页卡片是如何被选中、回流，以及何时才算真正完成。"),
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

struct FAQHeroCard: View {
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
        if AppColors.usesLightAppearance(themeMode: appState.themeMode, isDarkMode: isDarkMode) {
            return AppColors.lightCard
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

struct FAQAccordionCard: View {
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
        if AppColors.usesLightAppearance(themeMode: appState.themeMode, isDarkMode: isDarkMode) {
            return Color.black.opacity(0.08)
        }
        return isDarkMode ? AppColors.nocturneBorder : Color.white.opacity(0.68)
    }
    private var dividerColor: Color {
        isDarkMode ? AppColors.nocturneBorderSoft : Color.black.opacity(0.08)
    }
    private var fillColor: Color {
        if AppColors.usesLightAppearance(themeMode: appState.themeMode, isDarkMode: isDarkMode) {
            return AppColors.lightCard
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

struct LegalDocumentSheetView: View {
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

