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
    static let porcelainBackground = Color(red: 234.0 / 255.0, green: 234.0 / 255.0, blue: 234.0 / 255.0)
    static let porcelainCard = Color.white

    // MARK: - Nocturne Dark Theme (Cinematic)

    static let nocturneBackgroundTop = Color(red: 0.11, green: 0.10, blue: 0.11)
    static let nocturneBackgroundMid = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let nocturneBackgroundBottom = Color(red: 0.05, green: 0.05, blue: 0.06)

    static let nocturneSurface = Color(red: 0.15, green: 0.14, blue: 0.15)
    static let nocturneSurfaceElevated = Color(red: 0.18, green: 0.17, blue: 0.19)
    static let nocturneBorder = Color.white.opacity(0.14)
    static let nocturneBorderSoft = Color.white.opacity(0.08)

    static let nocturneTextPrimary = Color.white.opacity(0.92)
    static let nocturneTextSecondary = Color.white.opacity(0.64)
    static let nocturneTextTertiary = Color.white.opacity(0.48)

    static let nocturneWarmGlow = Color(red: 0.93, green: 0.54, blue: 0.33)
    static let nocturneCoolGlow = Color(red: 0.48, green: 0.66, blue: 1.00)
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
    static func appBackgroundGradient(themeMode: ThemeMode, isDarkMode: Bool) -> LinearGradient {
        switch themeMode {
        case .paper:
            return LinearGradient(
                colors: [
                    Color(red: 0.985, green: 0.955, blue: 0.900),
                    Color(red: 0.955, green: 0.905, blue: 0.810)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .graphite:
            return LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.09),
                    Color(red: 0.09, green: 0.11, blue: 0.14)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .porcelain:
            return LinearGradient(
                colors: [porcelainBackground, porcelainBackground],
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
        if themeMode == .porcelain {
            return porcelainCard
        }
        return isDarkMode ? nocturneSurface : Color(red: 0.965, green: 0.966, blue: 0.972)
    }

    static func elevatedSurfaceBorder(themeMode: ThemeMode = .system, isDarkMode: Bool) -> Color {
        if themeMode == .porcelain {
            return Color.black.opacity(0.08)
        }
        return isDarkMode ? nocturneBorder : Color.white.opacity(0.72)
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
