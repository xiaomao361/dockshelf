import Foundation

struct ShelfItem: Identifiable, Hashable {
    let url: URL
    let addedAt: Date

    var id: String { url.path }
    var displayName: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}

@MainActor
final class ShelfStore: ObservableObject {
    static let maximumItemCount = 20

    @Published private(set) var items: [ShelfItem] = []

    @discardableResult
    func add(_ urls: [URL]) -> Int {
        let initialCount = items.count
        var knownPaths = Set(items.map(\.url.path))

        for candidate in urls where items.count < Self.maximumItemCount {
            guard candidate.isFileURL else { continue }
            let url = candidate.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }
            guard knownPaths.insert(url.path).inserted else { continue }
            items.append(ShelfItem(url: url, addedAt: Date()))
        }

        return items.count - initialCount
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }
}
