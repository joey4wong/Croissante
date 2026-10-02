import SwiftUI

struct FavoritesListView: View {
    let words: [SimpleWord]

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }

    var body: some View {
        List {
            ForEach(words) { word in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(word.displayWord)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isDarkMode ? AppColors.nocturneTextPrimary : Color.black.opacity(0.82))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(appState.translationText(for: word))
                        .font(.system(size: 14))
                        .foregroundStyle(isDarkMode ? AppColors.nocturneTextSecondary : Color.black.opacity(0.44))
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.07))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        favoritesStore.toggleFavorite(wordId: word.id)
                    } label: {
                        Label(appState.localized("Remove", "移除"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.easeInOut(duration: 0.2), value: words.map(\.id))
    }
}

struct DiscoverEmptyStateView: View {
    let title: String
    let subtitle: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.50) : Color.black.opacity(0.34))
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.84) : Color.black.opacity(0.76))
            Text(subtitle)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.56) : Color.black.opacity(0.48))
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
