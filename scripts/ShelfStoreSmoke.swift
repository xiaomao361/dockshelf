import Foundation

@main
struct DockShelfStoreSmoke {
    @MainActor
    static func main() throws {
        let suiteName = "DockShelfStoreSmoke.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockShelfStoreSmoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let urls = try (0..<41).map { index -> URL in
            let url = root.appendingPathComponent("file-\(index).txt")
            try Data("\(index)".utf8).write(to: url)
            return url
        }

        let store = ShelfStore(defaults: defaults)
        check(store.add(Array(urls[0..<20])) == .added(count: 20), "adds first 20")
        check(store.add([urls[0]]) == .duplicate, "rejects an existing path")
        let originalIDs = store.items.map(\.id)

        store.togglePinned(store.items[0])
        check(store.items[0].isPinned, "pins an item")
        check(
            store.add([urls[20]]) == .replaced(addedCount: 1, removedCount: 1),
            "replaces oldest unpinned item"
        )
        check(store.items.contains(where: { $0.id == originalIDs[0] }), "keeps pinned oldest item")
        check(!store.items.contains(where: { $0.id == originalIDs[1] }), "removes oldest unpinned item")

        check(store.undoLastReplacement(), "undo is available")
        check(store.items.map(\.id) == originalIDs, "undo restores exact order")

        let restored = ShelfStore(defaults: defaults)
        check(restored.items.count == 1, "restores only pinned items")
        check(restored.items[0].id == originalIDs[0], "restores pinned path")

        let folderSuite = "\(suiteName).folder"
        guard let folderDefaults = UserDefaults(suiteName: folderSuite) else {
            fatalError("Unable to create folder test defaults")
        }
        defer { folderDefaults.removePersistentDomain(forName: folderSuite) }
        let folderStore = ShelfStore(defaults: folderDefaults)
        check(folderStore.add([root]) == .added(count: 1), "accepts a folder reference")
        check(
            folderStore.items[0].url.path == root.standardizedFileURL.path,
            "keeps the original folder path"
        )

        for item in store.items where !item.isPinned {
            store.togglePinned(item)
        }
        check(
            store.add([urls[20]]) == .insufficientReplaceable(required: 1, available: 0),
            "does not replace pinned items"
        )

        let oversizedSuite = "\(suiteName).oversized"
        guard let oversizedDefaults = UserDefaults(suiteName: oversizedSuite) else {
            fatalError("Unable to create oversized test defaults")
        }
        defer { oversizedDefaults.removePersistentDomain(forName: oversizedSuite) }
        let oversizedStore = ShelfStore(defaults: oversizedDefaults)
        check(
            oversizedStore.add(Array(urls[20..<41])) == .tooMany(limit: 20),
            "rejects a batch larger than 20"
        )

        print("ShelfStore smoke passed")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Failed: \(message)") }
    }
}
