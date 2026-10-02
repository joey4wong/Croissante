import Foundation

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var favoriteWordIds: [String]

    private let defaultsKey = "favoriteWordIds"
    var onChange: (() -> Void)?

    init() {
        favoriteWordIds = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }

    func isFavorite(_ id: String) -> Bool {
        favoriteWordIds.contains(id)
    }

    func toggleFavorite(wordId: String) {
        if let index = favoriteWordIds.firstIndex(of: wordId) {
            favoriteWordIds.remove(at: index)
        } else {
            favoriteWordIds.insert(wordId, at: 0)
        }
        persist(notify: true)
    }

    func remove(wordIds: Set<String>) {
        let filtered = favoriteWordIds.filter { !wordIds.contains($0) }
        guard filtered.count != favoriteWordIds.count else { return }
        favoriteWordIds = filtered
        persist(notify: true)
    }

    func removeAll() {
        guard !favoriteWordIds.isEmpty else { return }
        favoriteWordIds = []
        persist(notify: true)
    }

    func replaceFromICloudSync(_ ids: [String]) {
        var seen = Set<String>()
        let ordered = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard ordered != favoriteWordIds else { return }
        favoriteWordIds = ordered
        persist(notify: false)
    }

    func resolvedWords(from catalog: [SimpleWord]) -> [SimpleWord] {
        let byId = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return favoriteWordIds.compactMap { byId[$0] }
    }

    private func persist(notify: Bool) {
        UserDefaults.standard.set(favoriteWordIds, forKey: defaultsKey)
        if notify { onChange?() }
    }
}
