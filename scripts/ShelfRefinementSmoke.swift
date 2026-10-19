import AppKit
import UniformTypeIdentifiers

@main
struct ShelfRefinementSmoke {
    @MainActor
    static func main() async throws {
        let suite = "DockShelfRefinementSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try (0..<22).map { index in
            let url = root.appendingPathComponent("中文 file \(index) #.txt")
            try Data("original-\(index)".utf8).write(to: url)
            return url
        }
        let missing = root.appendingPathComponent("missing.txt")
        let store = ShelfStore(defaults: defaults)
        let interaction = ShelfInteractionState()
        let partial = store.add([files[0], files[0], missing], failedCount: 1)
        check(partial == .partial(addedCount: 1, removedCount: 0, duplicateCount: 1, failedCount: 2), "mixed batch preserves all outcome counts")
        check(store.lastImportIssues.count == 2, "each failed entry has recovery details without counting duplicates")
        check(store.lastImportIssues[0].url == nil && store.lastImportIssues[0].reason == .unknown, "unidentified receiver failure stays unknown")
        check(store.lastImportIssues[0].displayName == "无法识别的项目", "unidentified entries never guess a filename")
        check(store.lastImportIssues[1].url == missing && store.lastImportIssues[1].reason == .unavailable, "missing local file retains its exact identity")
        check(Set(store.lastImportIssues.map(\.id)).count == 2, "recovery entries have unique stable identities")
        check(partial.accepted && store.items.count == 1, "valid entries remain usable")
        interaction.finishDrop(result: partial)
        check(interaction.phase == .partial(addedCount: 1, removedCount: 0, duplicateCount: 1, failedCount: 2), "partial result is not normal success downstream")
        let nothingAdded = store.add([files[0], missing])
        check(!nothingAdded.accepted, "failed and duplicate-only batch is not accepted")
        check(store.lastImportIssues.count == 1 && store.lastImportIssues[0].url == missing, "latest import replaces old issue details")
        check(store.add([], failedCount: 2) == .invalid, "all provider failures remain invalid")
        check(store.lastImportIssues.count == 2 && store.lastImportIssues.allSatisfy { $0.url == nil && $0.reason == .unknown }, "all receiver failures retain explicit unknown details")
        let knownReceiverIssue = ShelfImportIssue(url: missing, reason: .unavailable)
        check(store.add([files[1]], failedCount: 2, issues: [knownReceiverIssue]) == .partial(addedCount: 1, removedCount: 0, duplicateCount: 0, failedCount: 2), "known recovery details do not double-count receiver failures")
        check(store.lastImportIssues.count == 2 && store.lastImportIssues[0] == knownReceiverIssue && store.lastImportIssues[1].reason == .unknown, "missing detail is filled without reducing reported failures")
        check(store.add([], failedCount: 1, issues: [knownReceiverIssue, ShelfImportIssue(reason: .unknown)]) == .invalid, "extra issue descriptions cannot change outcome count")
        check(store.lastImportIssues == [knownReceiverIssue], "recovery detail count follows receiver count")
        check(store.add([missing]) == .invalid && store.lastImportIssues.count == 1 && store.lastImportIssues[0].url == missing, "all missing local files remain identifiable failures")
        check(store.add([URL(string: "https://example.invalid/file")!]) == .invalid, "non-local candidate stays invalid")
        check(store.lastImportIssues.count == 1 && store.lastImportIssues[0].reason == .notLocalFile && store.lastImportIssues[0].url == nil, "non-local failure does not invent a local filename")
        check(store.add([files[2]]) == .added(count: 1) && store.lastImportIssues.isEmpty, "success clears stale failure details")
        check(store.add([files[0]]) == .duplicate && store.lastImportIssues.isEmpty, "duplicate-only result is not reported as unreadable")

        store.clearAll()
        check(store.add(Array(files.prefix(20))) == .added(count: 20), "capacity baseline")
        let originalOrder = store.items.map(\.id)
        let replaced = store.add([files[20], missing])
        check(replaced == .partial(addedCount: 1, removedCount: 1, duplicateCount: 0, failedCount: 1), "partial batch retains replacement count")
        check(store.canUndoReplacement, "partial replacement supports undo")
        check(store.undoLastReplacement(), "partial replacement undo succeeds")
        check(store.items.map(\.id) == originalOrder, "undo restores exact order")
        _ = store.add([files[20]])
        store.togglePinned(store.items[0])
        check(!store.canUndoReplacement && !store.undoLastReplacement(), "pin action invalidates undo availability")
        _ = store.add([files[21]])
        store.remove(store.items.last!)
        check(!store.canUndoReplacement, "remove action invalidates undo availability")
        for item in store.items where !item.isPinned { store.togglePinned(item) }
        let beforeRejected = store.items
        check(store.add([files[0], files[21]]) == .insufficientReplaceable(required: 1, available: 0), "capacity rejection remains atomic with pinned items")
        check(store.items == beforeRejected, "rejection preserves pinned content")

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        check(pasteboard.writeObjects([files[2] as NSURL, files[0] as NSURL, root as NSURL]), "native URL pasteboard writes")
        let native = ShelfImport.read(pasteboard)
        check(native.urls == [files[2], files[0], root] && native.failedCount == 0, "native file URLs retain source order, special paths and folders")
        check(native.issues.isEmpty, "successful native read has no failure details")
        check(ShelfImport.accepts(pasteboard), "native file drag is accepted")
        let nativeStore = ShelfStore(defaults: defaults)
        nativeStore.clearAll()
        check(nativeStore.add(native.urls, failedCount: native.failedCount, issues: native.issues) == .added(count: 3), "native drag reader reaches model successfully")

        pasteboard.clearContents()
        let validItem = NSPasteboardItem()
        validItem.setString(files[0].absoluteString, forType: .fileURL)
        let malformedItem = NSPasteboardItem()
        malformedItem.setString("https://example.invalid/file", forType: .fileURL)
        let textItem = NSPasteboardItem()
        textItem.setString("not a file", forType: .string)
        check(pasteboard.writeObjects([validItem, malformedItem, textItem]), "mixed pasteboard writes")
        let mixed = ShelfImport.read(pasteboard)
        check(mixed.urls == [files[0]] && mixed.failedCount == 2, "unsupported and non-file URLs remain explicit failures")
        check(mixed.issues.count == 2 && mixed.issues.allSatisfy { $0.url == nil && $0.reason == .unknown }, "native reader never assigns failed-item names from readObjects ordering")
        check(Set(mixed.issues.map(\.id)).count == 2, "unknown native failures remain separate recovery entries")
        nativeStore.clearAll()
        check(nativeStore.add(mixed.urls, failedCount: mixed.failedCount, issues: mixed.issues) == .partial(addedCount: 1, removedCount: 0, duplicateCount: 0, failedCount: 2), "native partial failure remains distinct downstream")
        check(nativeStore.lastImportIssues == mixed.issues, "native failure details reach the model without duplicating counts")

        pasteboard.clearContents()
        let unreadableItem = NSPasteboardItem()
        unreadableItem.setString("not a file", forType: .string)
        check(pasteboard.writeObjects([unreadableItem]), "unreadable-only pasteboard writes")
        let unreadable = ShelfImport.read(pasteboard)
        check(unreadable.urls.isEmpty && unreadable.failedCount == 1 && unreadable.issues.count == 1, "all unreadable native entries retain their failure count")
        check(nativeStore.add(unreadable.urls, failedCount: unreadable.failedCount, issues: unreadable.issues) == .invalid && nativeStore.lastImportIssues == unreadable.issues, "all unreadable native entries stay invalid with recovery details")

        pasteboard.clearContents()
        let selfItem = NSPasteboardItem()
        selfItem.setString(files[0].absoluteString, forType: .fileURL)
        selfItem.setString("own reference", forType: ShelfImport.sourceType)
        check(pasteboard.writeObjects([selfItem]), "own drag marker writes")
        check(ShelfImport.isShelfDrag(pasteboard) && !ShelfImport.accepts(pasteboard), "self-drop rejected by both entrances")
        pasteboard.clearContents()
        check(!ShelfImport.accepts(pasteboard) && ShelfImport.read(pasteboard).urls.isEmpty, "empty drag not accepted")

        var detection = ShelfDragDetection()
        check(!detection.update(changeCount: 1, hasFiles: true, isOwnDrag: false, point: .init(x: 100, y: 100), time: 1), "ordinary mouse movement cannot open shelf")
        detection.begin(changeCount: 10, point: .zero, time: 1)
        check(!detection.update(changeCount: 10, hasFiles: true, isOwnDrag: false, point: .init(x: 100, y: 0), time: 2), "stale file pasteboard cannot trigger text selection or window movement")
        check(!detection.update(changeCount: 11, hasFiles: false, isOwnDrag: false, point: .init(x: 100, y: 0), time: 2), "fresh text drag does not open shelf")
        check(!detection.update(changeCount: 11, hasFiles: true, isOwnDrag: true, point: .init(x: 100, y: 0), time: 2), "own outgoing drag does not open shelf")
        check(!detection.update(changeCount: 11, hasFiles: true, isOwnDrag: false, point: .init(x: 3, y: 0), time: 2), "tiny click movement does not open shelf")
        check(!detection.update(changeCount: 11, hasFiles: true, isOwnDrag: false, point: .init(x: 100, y: 0), time: 1.05), "drag settling delay prevents immediate flicker")
        check(detection.update(changeCount: 11, hasFiles: true, isOwnDrag: false, point: .init(x: 100, y: 0), time: 1.2), "fresh file drag opens automatically")
        check(!detection.update(changeCount: 11, hasFiles: true, isOwnDrag: false, point: .init(x: 200, y: 0), time: 2), "same drag does not chase pointer or repeatedly open")
        check(detection.end(), "release or cancel ends automatic presentation")
        check(!detection.end(), "duplicate release does not close another session")
        detection.begin(changeCount: 11, point: .zero, time: 3)
        check(!detection.update(changeCount: 11, hasFiles: true, isOwnDrag: false, point: .init(x: 100, y: 0), time: 4), "next mouse press ignores previous file data")
        check(detection.update(changeCount: 12, hasFiles: true, isOwnDrag: false, point: .init(x: 100, y: 0), time: 4), "next genuine drag can open again")
        _ = detection.end()

        let timers = ShelfPanelTimers()
        var completed = 0
        var hovered = 0
        timers.scheduleCompletion(after: 0.01) { completed += 1 }
        timers.scheduleTransient(after: 0.01) { hovered += 1 }
        timers.cancelTransient() // Same call used by both panel and status hover.
        try await Task.sleep(for: .milliseconds(50))
        check(completed == 1 && hovered == 0, "hover cannot cancel successful-drop dismissal")
        timers.scheduleCompletion(after: 0.01) { completed += 1 }
        timers.cancelCompletion() // Opening a new session must cancel the old close.
        try await Task.sleep(for: .milliseconds(50))
        check(completed == 1, "new session cancels stale completion")
        timers.scheduleCompletion(after: 0.01) { completed += 100 }
        timers.scheduleCompletion(after: 0.01) { completed += 1 }
        try await Task.sleep(for: .milliseconds(50))
        check(completed == 2, "only the latest completion timer fires")

        for (index, file) in files.enumerated() {
            check(try Data(contentsOf: file) == Data("original-\(index)".utf8), "source files remain unchanged")
        }
        print("Shelf refinement smoke passed: native drag URLs, ordering, folders, identifiable and unknown failures, failure-count fidelity, self-drop, undo, capacity, independent close timers, automatic drag lifecycle, source integrity")
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("Failed: \(message)") }
    }
}
