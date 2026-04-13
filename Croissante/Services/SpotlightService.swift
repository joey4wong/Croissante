import Foundation
import CoreSpotlight

@MainActor
final class SpotlightService {
    static let shared = SpotlightService()
    
    private init() {}
    
    private let domainIdentifier = "daily_french_word"
    private let chunkSize = 500
    private var reindexTask: Task<Void, Never>?
    
    func indexAllWords(_ words: [SimpleWord], conjugationFormsByLemma: [String: [String]]) {
        let previousTask = reindexTask
        previousTask?.cancel()
        reindexTask = Task { @MainActor [words, conjugationFormsByLemma, previousTask] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            await replaceAllWords(words, conjugationFormsByLemma: conjugationFormsByLemma)
        }
    }
    
    func removeAllWords() {
        let previousTask = reindexTask
        previousTask?.cancel()
        reindexTask = Task { @MainActor [previousTask] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            await deleteAllWordsAwaiting()
        }
    }
    
    func handleUserActivity(_ userActivity: NSUserActivity) -> String? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              identifier.hasPrefix("word_") else {
            return nil
        }
        return String(identifier.dropFirst("word_".count))
    }

    private func indexItemsInChunks(_ items: [CSSearchableItem]) async {
        guard !items.isEmpty else { return }
        for start in stride(from: 0, to: items.count, by: chunkSize) {
            guard !Task.isCancelled else { return }
            let end = min(start + chunkSize, items.count)
            await indexItemsAwaiting(Array(items[start..<end]))
        }
    }

    private func makeSearchableItem(for word: SimpleWord, conjugationFormsByLemma: [String: [String]]) -> CSSearchableItem {
        let uniqueIdentifier = "word_\(word.id)"
        let description = word.translationEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let lemma = SearchTextNormalizer.normalize(word.word)
        let forms = conjugationFormsByLemma[lemma] ?? []

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = word.word
        attributeSet.contentDescription = description.isEmpty
            ? word.level
            : "\(description) · \(word.level)"
        attributeSet.keywords = [
            word.word,
            word.translationEn,
            word.translationZh,
            word.level
        ] + forms

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
    
    private func replaceAllWords(_ words: [SimpleWord], conjugationFormsByLemma: [String: [String]]) async {
        await deleteAllWordsAwaiting()
        guard !Task.isCancelled else { return }
        let items = words.map { makeSearchableItem(for: $0, conjugationFormsByLemma: conjugationFormsByLemma) }
        await indexItemsInChunks(items)
    }

    private func indexItemsAwaiting(_ items: [CSSearchableItem]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CSSearchableIndex.default().indexSearchableItems(items) { _ in
                continuation.resume()
            }
        }
    }

    private func deleteAllWordsAwaiting() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in
                continuation.resume()
            }
        }
    }
}
