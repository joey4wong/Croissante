import SwiftUI
#if os(iOS)
import UIKit
#endif

enum MainTab: CaseIterable, Hashable {
    case explore
    case progress
    case settings
    case search
}

struct AppIconPickerLayout {
    let tileSize: CGFloat
    let contentInset: CGFloat
    let bottomInset: CGFloat
    let initialDropTopInset: CGFloat
    let initialDropSpacing: CGFloat

    var sheetInsets: EdgeInsets {
        EdgeInsets(
            top: contentInset,
            leading: contentInset,
            bottom: bottomInset,
            trailing: contentInset
        )
    }
}

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchSheetShowing = false
    @State private var selectedTab: MainTab = .explore
    @State private var lastContentTab: MainTab = .explore
    @State private var settingsGearSpinToken = 0

    public init() {}

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    @ViewBuilder
    private var wallpaperBackground: some View {
        ThemedBackgroundView(
            themeMode: appState.themeMode,
            isDarkMode: isDarkMode
        )
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            Tab(appState.localized("Explore", "探索"), systemImage: "siri", value: .explore) {
                HomeScreen(isActiveTab: selectedTab == .explore)
            }
            Tab(appState.localized("Progress", "进度"), systemImage: "figure.run.square.stack.fill", value: .progress) {
                ProgressScreen(isActiveTab: selectedTab == .progress)
                    .background { wallpaperBackground }
            }
            Tab(appState.localized("Settings", "设置"), systemImage: "gear", value: .settings) {
                SettingsScreen()
                    .background { wallpaperBackground }
            }
            Tab(appState.localized("Search", "搜索"), systemImage: "magnifyingglass", value: .search, role: .search) {
                Color.clear
                    .ignoresSafeArea()
            }
        }
        #if os(iOS)
        .background(
            SettingsTabGearAnimationBridge(
                settingsIndex: 2,
                spinToken: settingsGearSpinToken,
                isTabBarHidden: false
            )
            .frame(width: 0, height: 0)
        )
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .tint(Color(red: 0.02, green: 0.48, blue: 1.00))
        .onChange(of: selectedTab) { _, newTab in
            guard newTab == .search else {
                lastContentTab = newTab
                if newTab == .settings {
                    settingsGearSpinToken += 1
                }
                return
            }

            selectedTab = lastContentTab
            searchSheetShowing = true
        }
        .modifier(
            SearchPresentationModifier(
                isPresented: $searchSheetShowing,
                allWords: appState.words,
                searchIndex: appState.wordSearchIndex
            )
        )
    }
}

private struct SearchPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let allWords: [SimpleWord]
    let searchIndex: WordSearchIndex

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $isPresented) {
            SearchSheetView(
                isPresented: $isPresented,
                allWords: allWords,
                searchIndex: searchIndex,
                presentationStyle: .fullScreen
            )
        }
        #else
        content.sheet(isPresented: $isPresented) {
            SearchSheetView(
                isPresented: $isPresented,
                allWords: allWords,
                searchIndex: searchIndex,
                presentationStyle: .sheet
            )
        }
        #endif
    }
}
