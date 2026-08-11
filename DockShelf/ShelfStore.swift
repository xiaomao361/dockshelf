import Foundation
import Combine

struct ShelfItem: Identifiable, Hashable {
    let url: URL
    let addedAt: Date
    var isPinned: Bool

    var id: String { url.path }
    var displayName: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}

@MainActor
final class ShelfStore: ObservableObject {
    enum AddResult: Equatable {
        case added(count: Int)
        case replaced(addedCount: Int, removedCount: Int)
        case duplicate
        case invalid
        case tooMany(limit: Int)
        case insufficientReplaceable(required: Int, available: Int)

        var accepted: Bool {
            switch self {
            case .added, .replaced:
                true
            case .duplicate, .invalid, .tooMany, .insufficientReplaceable:
                false
            }
        }
    }

    static let maximumItemCount = 20

    @Published private(set) var items: [ShelfItem]

    private struct PersistedPinnedItem: Codable {
        let path: String
        let addedAt: Date
    }

    private static let pinnedItemsDefaultsKey = "DockShelf.pinnedItems.v1"

    private let defaults: UserDefaults
    private var replacementUndoSnapshot: [ShelfItem]?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        items = Self.loadPinnedItems(from: defaults)
    }

    @discardableResult
    func add(_ urls: [URL]) -> AddResult {
        var sawValidItem = false
        var incomingPaths = Set<String>()
        let existingPaths = Set(items.map(\.url.path))
        var incoming: [URL] = []

        for candidate in urls {
            guard candidate.isFileURL else { continue }
            let url = candidate.standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            sawValidItem = true
            guard !existingPaths.contains(url.path), incomingPaths.insert(url.path).inserted else {
                continue
            }
            incoming.append(url)
        }

        guard !incoming.isEmpty else {
            return sawValidItem ? .duplicate : .invalid
        }
        guard incoming.count <= Self.maximumItemCount else {
            return .tooMany(limit: Self.maximumItemCount)
        }

        let requiredReplacementCount = max(
            0,
            items.count + incoming.count - Self.maximumItemCount
        )
        let replaceableItems = items.filter { !$0.isPinned }
        guard replaceableItems.count >= requiredReplacementCount else {
            return .insufficientReplaceable(
                required: requiredReplacementCount,
                available: replaceableItems.count
            )
        }

        clearReplacementUndo()
        let previousItems = items

        if requiredReplacementCount > 0 {
            let replacedIDs = Set(
                replaceableItems.prefix(requiredReplacementCount).map(\.id)
            )
            items.removeAll { replacedIDs.contains($0.id) }
        }

        items.append(contentsOf: incoming.map {
            ShelfItem(url: $0, addedAt: Date(), isPinned: false)
        })

        if requiredReplacementCount > 0 {
            replacementUndoSnapshot = previousItems
            persistPinnedItems()
            return .replaced(
                addedCount: incoming.count,
                removedCount: requiredReplacementCount
            )
        }

        return .added(count: incoming.count)
    }

    func togglePinned(_ item: ShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        clearReplacementUndo()
        items[index].isPinned.toggle()
        persistPinnedItems()
    }

    func remove(_ item: ShelfItem) {
        clearReplacementUndo()
        items.removeAll { $0.id == item.id }
        persistPinnedItems()
    }

    func clearTemporaryItems() {
        clearReplacementUndo()
        items.removeAll { !$0.isPinned }
    }

    func clearAll() {
        clearReplacementUndo()
        items.removeAll()
        persistPinnedItems()
    }

    @discardableResult
    func undoLastReplacement() -> Bool {
        guard let replacementUndoSnapshot else { return false }
        items = replacementUndoSnapshot
        clearReplacementUndo()
        persistPinnedItems()
        return true
    }

    private func clearReplacementUndo() {
        replacementUndoSnapshot = nil
    }

    private func persistPinnedItems() {
        let pinnedItems = items
            .filter(\.isPinned)
            .map { PersistedPinnedItem(path: $0.url.path, addedAt: $0.addedAt) }
        guard let data = try? JSONEncoder().encode(pinnedItems) else { return }
        defaults.set(data, forKey: Self.pinnedItemsDefaultsKey)
    }

    private static func loadPinnedItems(from defaults: UserDefaults) -> [ShelfItem] {
        guard let data = defaults.data(forKey: pinnedItemsDefaultsKey),
              let persistedItems = try? JSONDecoder().decode(
                  [PersistedPinnedItem].self,
                  from: data
              ) else { return [] }

        var knownPaths = Set<String>()
        return persistedItems
            .sorted { $0.addedAt < $1.addedAt }
            .compactMap { item -> ShelfItem? in
                let url = URL(fileURLWithPath: item.path).standardizedFileURL
                guard knownPaths.insert(url.path).inserted else { return nil }
                return ShelfItem(url: url, addedAt: item.addedAt, isPinned: true)
            }
            .prefix(maximumItemCount)
            .map { $0 }
    }
}
