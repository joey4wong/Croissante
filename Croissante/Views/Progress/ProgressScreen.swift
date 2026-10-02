import SwiftUI

struct ProgressScreen: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @Environment(\.colorScheme) private var colorScheme
    let isActiveTab: Bool

    @State private var favoriteWordsSnapshot: [SimpleWord] = []

    private var isDarkMode: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 18) {
                Spacer().frame(height: 10)

                CheckInHeatmapView(isActive: isActiveTab)
                    .frame(height: 186)
                    .padding(.horizontal, 20)

                if favoriteWordsSnapshot.isEmpty {
                    DiscoverEmptyStateView(
                        title: appState.localized("No favorites yet", "暂无收藏"),
                        subtitle: appState.localized(
                            "Tap the graduation cap on a card to save it here.",
                            "在卡片上点击学位帽，就会收藏到这里。"
                        )
                    )
                    .padding(.horizontal, 24)
                } else {
                    FavoritesInteractiveRoot(
                        catalogWords: favoriteWordsSnapshot,
                        onDismiss: {}
                    )
                    .frame(width: geo.size.width, alignment: .top)
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear(perform: refreshSnapshot)
        .onChange(of: favoritesStore.favoriteWordIds) { _, _ in refreshSnapshot() }
        .onReceive(appState.$words) { _ in refreshSnapshot() }
    }

    private func refreshSnapshot() {
        favoriteWordsSnapshot = favoritesStore.resolvedWords(from: appState.words)
    }
}
