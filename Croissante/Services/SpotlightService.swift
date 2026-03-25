import Foundation
import CoreSpotlight

@MainActor
final class SpotlightService {
    static let shared = SpotlightService()
    
    private init() {}
    
    private let domainIdentifier = "daily_french_word"
    private let chunkSize = 120
    
    func indexAllWords(_ words: [SimpleWord], conjugationFormsByLemma: [String: [String]], spotlightEnabled: Bool) {
        guard spotlightEnabled else { return }
        indexItemsInChunks(makeSearchableItems(words, conjugationFormsByLemma: conjugationFormsByLemma))
    }
    
    func removeAllWords() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in }
    }
    
    func handleUserActivity(_ userActivity: NSUserActivity) -> String? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              identifier.hasPrefix("word_") else {
            return nil
        }
        return String(identifier.dropFirst("word_".count))
    }

    private func makeSearchableItems(_ words: [SimpleWord], conjugationFormsByLemma: [String: [String]]) -> [CSSearchableItem] {
        words.map { makeSearchableItem(for: $0, conjugationFormsByLemma: conjugationFormsByLemma) }
    }

    private func indexItemsInChunks(_ items: [CSSearchableItem]) {
        guard !items.isEmpty else { return }
        for start in stride(from: 0, to: items.count, by: chunkSize) {
            let end = min(start + chunkSize, items.count)
            indexItems(Array(items[start..<end]))
        }
    }

    private func makeSearchableItem(for word: SimpleWord, conjugationFormsByLemma: [String: [String]]) -> CSSearchableItem {
        let uniqueIdentifier = "word_\(word.id)"
        let description = word.translationEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let lemma = SearchTextNormalizer.normalize(word.word)
        let forms = conjugationFormsByLemma[lemma] ?? []
        let formsText = forms.isEmpty ? "" : " • \(forms.prefix(12).joined(separator: " "))"

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = word.word
        attributeSet.contentDescription = description.isEmpty
            ? "\(word.level)\(formsText)"
            : "\(description) · \(word.level)\(formsText)"
        attributeSet.keywords = [
            word.word,
            word.translationEn,
            word.translationZh,
            word.level
        ] + forms.prefix(5)

        let alternateNames = Array(forms.prefix(3))
        if !alternateNames.isEmpty {
            attributeSet.alternateNames = alternateNames
        }

        return CSSearchableItem(
            uniqueIdentifier: uniqueIdentifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }
    
    private func indexItems(_ items: [CSSearchableItem]) {
        guard !items.isEmpty else { return }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }
}
