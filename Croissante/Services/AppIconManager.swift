import SwiftUI

#if canImport(UIKit)
import UIKit
import Foundation
#endif

@MainActor
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()
    
    struct AppIcon: Identifiable, Equatable {
        let id: String
        let iconName: String?
        let previewAssetName: String
        
        static let allIcons: [AppIcon] = [
            AppIcon(id: "default", iconName: nil, previewAssetName: "AppIconPreview-Default"),
            AppIcon(id: "neon", iconName: "AppIcon-Neon", previewAssetName: "AppIconPreview-Neon"),
            AppIcon(id: "washi", iconName: "AppIcon-Washi", previewAssetName: "AppIconPreview-Washi"),
            AppIcon(id: "landscape", iconName: "AppIcon-Landscape", previewAssetName: "AppIconPreview-Landscape"),
            AppIcon(id: "gold", iconName: "AppIcon-Gold", previewAssetName: "AppIconPreview-Gold"),
            AppIcon(id: "crystal", iconName: "AppIcon-Crystal", previewAssetName: "AppIconPreview-Crystal"),
            AppIcon(id: "ivory", iconName: "AppIcon-Ivory", previewAssetName: "AppIconPreview-Ivory"),
            AppIcon(id: "icon08", iconName: "AppIcon-08", previewAssetName: "AppIconPreview-08"),
            AppIcon(id: "icon09", iconName: "AppIcon-09", previewAssetName: "AppIconPreview-09")
        ]

        static let defaultIcon: AppIcon = allIcons[0]
        private static let iconsByAlternateName: [String: AppIcon] = Dictionary(
            uniqueKeysWithValues: allIcons.compactMap { icon in
                guard let iconName = icon.iconName else { return nil }
                return (iconName, icon)
            }
        )
        static let freeIconIDs: Set<String> = ["default"]

        static func from(iconName: String?) -> AppIcon {
            guard let iconName else { return defaultIcon }
            return iconsByAlternateName[iconName] ?? defaultIcon
        }
    }
    
    @Published private(set) var currentIcon: AppIcon = .defaultIcon
    @Published private(set) var changingIcon: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let iconKey = "appIconName"
    
    private init() {
        loadCurrentIcon()
    }
    
    private func loadCurrentIcon() {
        let iconName: String?
        #if os(iOS)
        #if targetEnvironment(simulator)
        // Simulator fallback: when icon API is bypassed we persist local selection.
        iconName = userDefaults.string(forKey: iconKey)
        #else
        // Real device source of truth should be system state.
        iconName = UIApplication.shared.alternateIconName
        #endif
        #else
        iconName = userDefaults.string(forKey: iconKey)
        #endif

        currentIcon = icon(for: iconName)
    }

    private func persistCurrentIconName(_ iconName: String?) {
        #if os(iOS) && !targetEnvironment(simulator)
        return
        #else
        if let iconName {
            userDefaults.set(iconName, forKey: iconKey)
        } else {
            userDefaults.removeObject(forKey: iconKey)
        }
        #endif
    }

    func icon(for iconName: String?) -> AppIcon {
        AppIcon.from(iconName: iconName)
    }

    func refreshCurrentIcon() {
        loadCurrentIcon()
    }

    private func applyLocalSelection(_ icon: AppIcon) {
        currentIcon = icon
        persistCurrentIconName(icon.iconName)
    }
    
    func changeIcon(to icon: AppIcon) async throws {
        guard !changingIcon else { return }
        
        changingIcon = true
        defer { changingIcon = false }
        
        #if os(iOS)
        guard UIApplication.shared.supportsAlternateIcons else {
            throw AppIconError.unsupportedOS
        }

        #if targetEnvironment(simulator)
        if #available(iOS 26.1, *) {
            // iOS 26.1+ simulator may repeatedly fail setAlternateIconName with POSIX EAGAIN.
            // Keep simulator UX stable while preserving real-device behavior.
            applyLocalSelection(icon)
            return
        }
        #endif

        guard isIconConfigured(icon.iconName) else {
            throw AppIconError.iconNotConfigured
        }
        if isCurrentAlternateIconName(icon.iconName) {
            applyLocalSelection(icon)
            return
        }

        try await setAlternateIconNameWithRetry(icon.iconName)
        applyLocalSelection(icon)
        #else
        applyLocalSelection(icon)
        #endif
    }

    #if os(iOS)
    private func setAlternateIconNameWithRetry(_ iconName: String?) async throws {
        try await waitForActiveSceneIfNeeded()

        let retryDelays: [UInt64] = [
            0,
            250_000_000,
            600_000_000,
            1_100_000_000
        ]

        for delay in retryDelays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }

            do {
                try await setAlternateIconName(iconName)
            } catch {
                if isCurrentAlternateIconName(iconName) {
                    return
                }

                if isTransientResourceError(error) {
                    continue
                }

                throw error
            }

            if isCurrentAlternateIconName(iconName) {
                return
            }
        }

        if isCurrentAlternateIconName(iconName) {
            return
        }

        throw AppIconError.temporarilyUnavailable
    }

    private func setAlternateIconName(_ iconName: String?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UIApplication.shared.setAlternateIconName(iconName) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func isTransientResourceError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == 35 {
            return true
        }
        let message = nsError.localizedDescription.lowercased()
        return message.contains("resource temporarily unavailable")
    }

    private func isCurrentAlternateIconName(_ iconName: String?) -> Bool {
        UIApplication.shared.alternateIconName == iconName
    }

    private func isIconConfigured(_ iconName: String?) -> Bool {
        guard let iconName else { return true }
        guard let info = Bundle.main.infoDictionary else { return false }

        let iconDictionaries: [[String: Any]] = [
            info["CFBundleIcons"] as? [String: Any],
            info["CFBundleIcons~ipad"] as? [String: Any]
        ].compactMap { $0 }

        for icons in iconDictionaries {
            guard let alternates = icons["CFBundleAlternateIcons"] as? [String: Any] else { continue }
            if alternates[iconName] != nil {
                return true
            }
        }
        return false
    }

    private func waitForActiveSceneIfNeeded(maxWaitNanoseconds: UInt64 = 1_500_000_000) async throws {
        guard !hasForegroundActiveScene else { return }

        let pollNanoseconds: UInt64 = 150_000_000
        var waited: UInt64 = 0

        while waited < maxWaitNanoseconds {
            try await Task.sleep(nanoseconds: pollNanoseconds)
            if hasForegroundActiveScene {
                return
            }
            waited += pollNanoseconds
        }
    }

    private var hasForegroundActiveScene: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains(where: { $0.activationState == .foregroundActive })
    }
    #endif
}

enum AppIconError: LocalizedError {
    case unsupportedOS
    case temporarilyUnavailable
    case iconNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "此设备不支持动态应用图标"
        case .temporarilyUnavailable:
            return "系统暂时忙碌，请稍后重试"
        case .iconNotConfigured:
            return "图标资源配置不完整，请更新应用后重试"
        }
    }
}
