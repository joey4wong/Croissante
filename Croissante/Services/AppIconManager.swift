import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()
    
    struct AppIcon: Identifiable {
        let id: String
        let displayName: String
        let iconName: String?
        let previewColor: Color
        
        static let availableIcons: [AppIcon] = [
            AppIcon(id: "default", displayName: "默认", iconName: nil, previewColor: .blue),
            AppIcon(id: "berry", displayName: "浆果", iconName: "AppIcon-Berry", previewColor: .purple),
            AppIcon(id: "cream", displayName: "奶油", iconName: "AppIcon-Cream", previewColor: .orange),
            AppIcon(id: "midnight", displayName: "午夜", iconName: "AppIcon-Midnight", previewColor: .indigo)
        ]
    }
    
    @Published private(set) var currentIcon: AppIcon = .availableIcons[0]
    @Published private(set) var changingIcon: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let iconKey = "appIconName"
    
    private init() {
        loadCurrentIcon()
    }
    
    private func loadCurrentIcon() {
        let savedIconName = userDefaults.string(forKey: iconKey)
        currentIcon = AppIcon.availableIcons.first(where: { $0.iconName == savedIconName }) ?? AppIcon.availableIcons[0]
    }

    private func persistCurrentIconName(_ iconName: String?) {
        if let iconName {
            userDefaults.set(iconName, forKey: iconKey)
        } else {
            userDefaults.removeObject(forKey: iconKey)
        }
    }
    
    func changeIcon(to icon: AppIcon) async throws {
        guard !changingIcon else { return }
        
        changingIcon = true
        defer { changingIcon = false }
        
        let iconName = icon.iconName
        
        #if os(iOS)
        try await UIApplication.shared.setAlternateIconName(iconName)
        currentIcon = icon
        persistCurrentIconName(iconName)
        #else
        currentIcon = icon
        persistCurrentIconName(iconName)
        #endif
    }
}

enum AppIconError: LocalizedError {
    case unsupportedOS
    
    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "此设备不支持动态应用图标"
        }
    }
}
