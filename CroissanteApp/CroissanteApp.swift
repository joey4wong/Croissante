import SwiftUI
import UIKit
import CoreSpotlight

@main
struct CroissanteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: AppState
    @StateObject private var storeKitManager: StoreKitManager
    @StateObject private var srsManager = SRSManager.shared

    init() {
        let appState = AppState()
        _appState = StateObject(wrappedValue: appState)
        _storeKitManager = StateObject(wrappedValue: StoreKitManager(appState: appState))
        configureTabBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(storeKitManager)
                .environmentObject(srsManager)
                .preferredColorScheme(preferredColorScheme)
                .onAppear {
                    srsManager.configure(with: appState)
                    configureTabBarAppearance()
                }
                .onChange(of: appState.themeMode) { _, _ in
                    animateThemeSwitch()
                    configureTabBarAppearance()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        srsManager.refreshForCurrentDayIfNeeded()
                        Task {
                            await storeKitManager.syncMembershipStatus()
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    srsManager.refreshForCurrentDayIfNeeded()
                }
                #if os(iOS)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    srsManager.refreshForCurrentDayIfNeeded()
                }
                #endif
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let wordId = SpotlightService.shared.handleUserActivity(activity) {
                        appState.spotlightSelectedWordId = wordId
                    }
                }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appState.themeMode {
        case .system: return nil
        case .steppe: return .light
        case .dark: return .dark
        case .light: return .light
        }
    }

    private func configureTabBarAppearance() {
        let blue = UIColor.systemBlue
        let normal = UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.68)
            }
            return UIColor.black.withAlphaComponent(0.56)
        }

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        applyTabItemColors(to: appearance.stackedLayoutAppearance, selected: blue, normal: normal)
        applyTabItemColors(to: appearance.inlineLayoutAppearance, selected: blue, normal: normal)
        applyTabItemColors(to: appearance.compactInlineLayoutAppearance, selected: blue, normal: normal)

        appearance.selectionIndicatorImage = makeSelectionIndicatorImage()

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private func makeSelectionIndicatorImage() -> UIImage {
        let canvas = CGSize(width: 96, height: 44)
        let pill = CGRect(x: 14, y: 5, width: 68, height: 34)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let image = renderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))
            UIBezierPath(roundedRect: pill, cornerRadius: 17).addClip()
            UIColor.white.withAlphaComponent(0.80).setFill()
            ctx.fill(pill)
        }
        return image.resizableImage(
            withCapInsets: UIEdgeInsets(top: 20, left: 48, bottom: 20, right: 48),
            resizingMode: .stretch
        )
    }

    private func applyTabItemColors(
        to appearance: UITabBarItemAppearance,
        selected: UIColor,
        normal: UIColor
    ) {
        appearance.selected.iconColor = selected
        appearance.selected.titleTextAttributes = [.foregroundColor: selected]
        appearance.normal.iconColor = normal
        appearance.normal.titleTextAttributes = [.foregroundColor: normal]
    }

    @MainActor
    private func animateThemeSwitch() {
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return
        }

        UIView.transition(
            with: window,
            duration: 0.28,
            options: [.transitionCrossDissolve, .allowAnimatedContent]
        ) {}
        #endif
    }
}
