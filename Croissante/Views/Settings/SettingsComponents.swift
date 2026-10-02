import SwiftUI
#if os(iOS)
import UIKit
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

