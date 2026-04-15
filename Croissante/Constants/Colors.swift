import SwiftUI

// MARK: - Color Constants for SwiftUI

/// Application-wide color constants
/// Use these constants for consistency and easy theme changes

struct AppColors {
    // Background colors
    static let darkBackground = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let darkBackgroundSecondary = Color(red: 0.04, green: 0.05, blue: 0.08)
    static let lightBackground = Color(red: 0.97, green: 0.98, blue: 0.99)
    static let lightBackgroundSecondary = Color(red: 0.98, green: 0.98, blue: 1.0)
    static let lightBackgroundTertiary = Color(red: 0.96, green: 0.97, blue: 0.99)
    
    // Card colors
    static let darkCard = Color(red: 0.10, green: 0.12, blue: 0.16)
    static let darkCardSecondary = Color(red: 0.15, green: 0.16, blue: 0.20)
    static let lightCard = Color.white
    static let lightCardSecondary = Color(red: 0.95, green: 0.96, blue: 0.97)
    
    // Text colors
    static let darkTextPrimary = Color.white
    static let darkTextSecondary = Color(red: 0.56, green: 0.56, blue: 0.58)
    static let darkTextTertiary = Color(red: 0.55, green: 0.58, blue: 0.63)
    static let lightTextPrimary = Color(red: 0.07, green: 0.09, blue: 0.15)
    static let lightTextSecondary = Color.black.opacity(0.54)
    static let lightTextTertiary = Color(red: 0.55, green: 0.58, blue: 0.63)
    
    // Accent colors
    static let accentGreen = Color(red: 0.20, green: 0.77, blue: 0.49)
    static let accentGreenLight = Color(red: 0.26, green: 0.97, blue: 0.64)
    static let accentGreenBright = Color(red: 0.32, green: 1.0, blue: 0.68)
    static let accentBlue = Color(red: 0.30, green: 0.55, blue: 1.0)
    static let accentBlueLight = Color(red: 0.61, green: 0.78, blue: 1.0)
    static let accentTeal = Color(red: 0.46, green: 0.85, blue: 0.78)
    static let accentTealLight = Color(red: 0.72, green: 0.93, blue: 0.89)
    
    static let checkinHeatmapBg = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let checkinHeatmapLightBg = Color(red: 0.91, green: 0.92, blue: 0.93)
    static let lightAppearanceBackground = Color(red: 234.0 / 255.0, green: 234.0 / 255.0, blue: 234.0 / 255.0)

    // MARK: - Nocturne Dark Theme (Cinematic)

    static let nocturneBackgroundTop = Color(red: 0.20, green: 0.18, blue: 0.17)
    static let nocturneBackgroundMid = Color(red: 0.12, green: 0.11, blue: 0.11)
    static let nocturneBackgroundBottom = Color(red: 0.07, green: 0.06, blue: 0.07)

    static let nocturneSurface = Color(red: 0.17, green: 0.15, blue: 0.14)
    static let nocturneSurfaceElevated = Color(red: 0.20, green: 0.17, blue: 0.16)
    static let nocturneBorder = Color.white.opacity(0.18)
    static let nocturneBorderSoft = Color.white.opacity(0.09)

    static let nocturneTextPrimary = Color.white.opacity(0.92)
    static let nocturneTextSecondary = Color.white.opacity(0.64)
    static let nocturneTextTertiary = Color.white.opacity(0.48)

    static let nocturneWarmGlow = Color(red: 0.84, green: 0.58, blue: 0.41)
    static let nocturneCoolGlow = Color(red: 0.76, green: 0.82, blue: 0.92)
    static let iosSystemBlueDark = Color(red: 0.04, green: 0.52, blue: 1.00)
    static let iosSystemBlueLight = Color(red: 0.00, green: 0.48, blue: 1.00)
}

// MARK: - Color Extensions

extension Color {
    /// Initialize color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Semantic Theme Tokens

extension AppColors {
    static func usesLightAppearance(themeMode: ThemeMode, isDarkMode: Bool) -> Bool {
        themeMode == .light || (themeMode == .system && !isDarkMode)
    }

    static func usesDarkGlassStyle(themeMode: ThemeMode, isDarkMode: Bool) -> Bool {
        !usesLightAppearance(themeMode: themeMode, isDarkMode: isDarkMode) && isDarkMode
    }

    static func appBackgroundGradient(themeMode: ThemeMode, isDarkMode: Bool) -> LinearGradient {
        switch themeMode {
        case _ where usesLightAppearance(themeMode: themeMode, isDarkMode: isDarkMode):
            return LinearGradient(
                colors: [lightAppearanceBackground, lightAppearanceBackground],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            return appBackgroundGradient(isDarkMode: isDarkMode)
        }
    }

    static func appBackgroundGradient(isDarkMode: Bool) -> LinearGradient {
        LinearGradient(
            colors: isDarkMode
                ? [nocturneBackgroundTop, nocturneBackgroundMid, nocturneBackgroundBottom]
                : [
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    Color(red: 0.93, green: 0.95, blue: 0.97)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func elevatedSurfaceFill(themeMode: ThemeMode = .system, isDarkMode: Bool) -> Color {
        if usesLightAppearance(themeMode: themeMode, isDarkMode: isDarkMode) {
            return lightCard
        }
        return isDarkMode ? nocturneSurface.opacity(0.72) : Color(red: 0.965, green: 0.966, blue: 0.972)
    }

    static func elevatedSurfaceBorder(themeMode: ThemeMode = .system, isDarkMode: Bool) -> Color {
        if usesLightAppearance(themeMode: themeMode, isDarkMode: isDarkMode) {
            return Color.black.opacity(0.08)
        }
        return isDarkMode ? nocturneBorder : Color.white.opacity(0.72)
    }

    static func elevatedSurfaceBaseStyle(themeMode: ThemeMode = .system, isDarkMode: Bool, elevated: Bool = false) -> AnyShapeStyle {
        if usesLightAppearance(themeMode: themeMode, isDarkMode: isDarkMode) {
            return AnyShapeStyle(lightCard)
        }
        if isDarkMode {
            return AnyShapeStyle(elevated ? .thinMaterial : .ultraThinMaterial)
        }
        return AnyShapeStyle(Color(red: 0.965, green: 0.966, blue: 0.972))
    }

    static func elevatedSurfaceTint(themeMode: ThemeMode = .system, isDarkMode: Bool, elevated: Bool = false) -> Color {
        if usesLightAppearance(themeMode: themeMode, isDarkMode: isDarkMode) {
            return lightCard
        }
        if isDarkMode {
            return (elevated ? nocturneSurfaceElevated : nocturneSurface).opacity(elevated ? 0.58 : 0.66)
        }
        return Color(red: 0.965, green: 0.966, blue: 0.972).opacity(0.94)
    }

    static func elevatedSurfaceInnerBorder(themeMode: ThemeMode = .system, isDarkMode: Bool, elevated: Bool = false) -> Color {
        if usesLightAppearance(themeMode: themeMode, isDarkMode: isDarkMode) {
            return Color.white.opacity(0.55)
        }
        if isDarkMode {
            return Color.white.opacity(elevated ? 0.08 : 0.06)
        }
        return Color.white.opacity(0.82)
    }

    static func elevatedSurfaceGlowStyle(themeMode: ThemeMode = .system, isDarkMode: Bool, elevated: Bool = false) -> AnyShapeStyle {
        guard usesDarkGlassStyle(themeMode: themeMode, isDarkMode: isDarkMode) else {
            return AnyShapeStyle(Color.clear)
        }
        return AnyShapeStyle(
            RadialGradient(
                colors: [
                    nocturneWarmGlow.opacity(elevated ? 0.15 : 0.11),
                    Color(red: 0.91, green: 0.87, blue: 0.83).opacity(elevated ? 0.05 : 0.035),
                    Color.clear
                ],
                center: UnitPoint(x: 0.42, y: 0.68),
                startRadius: 24,
                endRadius: 320
            )
        )
    }

    static func elevatedSurfaceHighlightStyle(themeMode: ThemeMode = .system, isDarkMode: Bool, elevated: Bool = false) -> AnyShapeStyle {
        guard usesDarkGlassStyle(themeMode: themeMode, isDarkMode: isDarkMode) else {
            return AnyShapeStyle(Color.clear)
        }
        return AnyShapeStyle(
            RadialGradient(
                colors: [
                    Color.white.opacity(elevated ? 0.14 : 0.11),
                    Color.white.opacity(0.04),
                    Color.clear
                ],
                center: UnitPoint(x: 0.38, y: 0.28),
                startRadius: 16,
                endRadius: 280
            )
        )
    }

    static func primaryText(isDarkMode: Bool) -> Color {
        isDarkMode ? nocturneTextPrimary : Color(red: 0.08, green: 0.11, blue: 0.20)
    }

    static func secondaryText(isDarkMode: Bool) -> Color {
        isDarkMode ? nocturneTextSecondary : Color.black.opacity(0.44)
    }

    static func tertiaryText(isDarkMode: Bool) -> Color {
        isDarkMode ? nocturneTextTertiary : Color.black.opacity(0.30)
    }

    static func iosSystemBlue(isDarkMode: Bool) -> Color {
        isDarkMode ? iosSystemBlueDark : iosSystemBlueLight
    }
}

struct ThemedBackgroundView: View {
    let themeMode: ThemeMode
    let isDarkMode: Bool
    var showWallpaper: Bool = false

    var body: some View {
        ZStack {
            AppColors.appBackgroundGradient(themeMode: themeMode, isDarkMode: isDarkMode)
                .ignoresSafeArea()
            if AppColors.usesDarkGlassStyle(themeMode: themeMode, isDarkMode: isDarkMode) {
                GeometryReader { proxy in
                    ZStack {
                        ambientGlow(
                            color: AppColors.nocturneWarmGlow.opacity(0.24),
                            width: proxy.size.width * 1.02,
                            height: proxy.size.height * 0.44,
                            x: proxy.size.width * 0.16,
                            y: proxy.size.height * 0.86,
                            blur: 86
                        )
                        ambientGlow(
                            color: Color(red: 0.96, green: 0.91, blue: 0.87).opacity(0.16),
                            width: proxy.size.width * 0.78,
                            height: proxy.size.height * 0.34,
                            x: proxy.size.width * 0.92,
                            y: proxy.size.height * 0.18,
                            blur: 72
                        )
                        ambientGlow(
                            color: Color(red: 0.49, green: 0.31, blue: 0.24).opacity(0.10),
                            width: proxy.size.width * 0.72,
                            height: proxy.size.height * 0.26,
                            x: proxy.size.width * 0.18,
                            y: proxy.size.height * 0.34,
                            blur: 60
                        )
                    }
                    .ignoresSafeArea()
                }
                .allowsHitTesting(false)
            }
            if showWallpaper {
                Image("HomeWallpaperDefault")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }
        }
    }

    private func ambientGlow(color: Color, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat, blur: CGFloat) -> some View {
        Ellipse()
            .fill(color)
            .frame(width: width, height: height)
            .position(x: x, y: y)
            .blur(radius: blur)
    }
}

extension InsettableShape {
    func themedGlassSurface(themeMode: ThemeMode = .system, isDarkMode: Bool, elevated: Bool = false) -> some View {
        self
            .fill(AppColors.elevatedSurfaceBaseStyle(themeMode: themeMode, isDarkMode: isDarkMode, elevated: elevated))
            .overlay {
                self.fill(AppColors.elevatedSurfaceTint(themeMode: themeMode, isDarkMode: isDarkMode, elevated: elevated))
            }
            .overlay {
                self.fill(AppColors.elevatedSurfaceGlowStyle(themeMode: themeMode, isDarkMode: isDarkMode, elevated: elevated))
            }
            .overlay {
                self.fill(AppColors.elevatedSurfaceHighlightStyle(themeMode: themeMode, isDarkMode: isDarkMode, elevated: elevated))
            }
            .overlay {
                self.stroke(AppColors.elevatedSurfaceBorder(themeMode: themeMode, isDarkMode: isDarkMode), lineWidth: 1)
            }
            .overlay {
                self.inset(by: 1)
                    .stroke(AppColors.elevatedSurfaceInnerBorder(themeMode: themeMode, isDarkMode: isDarkMode, elevated: elevated), lineWidth: 0.8)
            }
    }
}
