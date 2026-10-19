import Foundation

@main
struct ShelfInteractionSmoke {
    @MainActor
    static func main() throws {
        let suite = "DockShelfInteractionSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try (0..<23).map { index in
            let url = root.appendingPathComponent("file-\(index).txt")
            try Data("original-\(index)".utf8).write(to: url)
            return url
        }
        let missing = root.appendingPathComponent("missing.txt")
        let store = ShelfStore(defaults: defaults)
        let interaction = ShelfInteractionState()

        interaction.showDropTarget(isValid: false)
        interaction.cancelDropTarget()
        check(interaction.phase == .idle && interaction.lastAddedCount == 0, "cancelling a first invalid drag is not success")

        _ = store.add(Array(files.prefix(20)))
        let originalOrder = store.items.map(\.id)
        interaction.finishDrop(result: store.add([files[20], files[21]]))
        check(interaction.phase == .replaced(count: 2) && interaction.lastAddedCount == 2, "replacement records actual added count")

        // The status-item path can send many updates before the drag exits.
        interaction.showDropTarget(isValid: true)
        interaction.showDropTarget(isValid: false)
        interaction.showDropTarget(isValid: true)
        interaction.cancelDropTarget()
        check(interaction.phase == .replaced(count: 2), "cancelled status drag restores replacement feedback across updates")
        check(store.canUndoReplacement && interaction.lastAddedCount == 2, "cancelled status drag retains undo and count")

        var panelExitObservedRestoredFeedback = false
        interaction.panelDropChanged = { active in
            if !active { panelExitObservedRestoredFeedback = interaction.hasPersistentFeedback }
        }
        interaction.panelDropEntered(isValid: true)
        interaction.panelDropExited()
        check(interaction.phase == .replaced(count: 2) && panelExitObservedRestoredFeedback, "panel exit restores feedback before its controller chooses whether to close")
        check(store.undoLastReplacement() && store.items.map(\.id) == originalOrder, "undo remains usable after both cancelled drop entrances")
        interaction.isShowingDetails = true
        interaction.showReplacementRestored()
        check(interaction.phase == .restored && interaction.lastAddedCount == 0 && !interaction.isShowingDetails, "undo clears the added count and stale details")

        let partial = store.add([files[20], missing], failedCount: 1)
        interaction.finishDrop(result: partial)
        let partialPhase = ShelfInteractionState.Phase.partial(addedCount: 1, removedCount: 1, duplicateCount: 0, failedCount: 2)
        check(interaction.phase == partialPhase && interaction.lastAddedCount == 1, "partial replacement keeps successful and failed counts separate")
        interaction.isShowingDetails = true
        interaction.panelDropEntered(isValid: false)
        check(!interaction.isShowingDetails, "a new drag closes the old recovery popover")
        interaction.showDropTarget(isValid: true)
        interaction.panelDropExited()
        check(interaction.phase == partialPhase && store.canUndoReplacement && !interaction.isShowingDetails, "cancelled panel drag restores feedback and undo without reopening old details")
        interaction.showDropTarget(isValid: false)
        interaction.cancelDropTarget()
        check(interaction.phase == partialPhase && interaction.lastAddedCount == 1, "cancelled status drag restores partial feedback")

        interaction.showDropTarget(isValid: true)
        interaction.isShowingDetails = true
        interaction.finishDrop(result: .invalid)
        interaction.cancelDropTarget()
        check(interaction.phase == .invalid && interaction.lastAddedCount == 0 && !interaction.isShowingDetails, "a real failed drop replaces old feedback and closes its details without becoming success")
        interaction.showDropTarget(isValid: true)
        interaction.cancelDropTarget()
        check(interaction.phase == .invalid, "cancelling another drag preserves the new failure rather than old partial feedback")

        store.clearAll()
        interaction.showDropTarget(isValid: true)
        interaction.finishDrop(result: store.add([files[22]]))
        check(interaction.phase == .success && interaction.lastAddedCount == 1, "a real successful drop replaces old failure and records its count")
        for result in [ShelfStore.AddResult.duplicate, .invalid, .tooMany(limit: 20), .insufficientReplaceable(required: 2, available: 0)] {
            interaction.finishDrop(result: result)
            let failedPhase = interaction.phase
            check(interaction.lastAddedCount == 0 && failedPhase != .success, "rejected drops never retain a successful count")
            interaction.panelDropEntered(isValid: true)
            interaction.panelDropExited()
            check(interaction.phase == failedPhase, "cancelling a drag preserves each actionable rejection")
        }
        interaction.finishDrop(result: .partial(addedCount: 0, removedCount: 0, duplicateCount: 1, failedCount: 1))
        check(interaction.phase == .partial(addedCount: 0, removedCount: 0, duplicateCount: 1, failedCount: 1) && interaction.lastAddedCount == 0, "a mixed batch with nothing added remains partial rather than success")

        interaction.finishDrop(result: partial)
        interaction.showDropTarget(isValid: true)
        interaction.isShowingDetails = true
        interaction.reset()
        interaction.showDropTarget(isValid: true)
        interaction.cancelDropTarget()
        check(interaction.phase == .idle && interaction.lastAddedCount == 0 && !interaction.isShowingDetails, "reset clears pending feedback, counts and details state")
        interaction.finishDrop(result: partial)
        interaction.isShowingDetails = true
        interaction.dismissFeedback()
        interaction.showDropTarget(isValid: true)
        interaction.cancelDropTarget()
        check(interaction.phase == .idle && interaction.lastAddedCount == 0 && !interaction.isShowingDetails, "dismissed feedback and details cannot be resurrected by a later cancellation")

        interaction.isShowingDetails = true
        interaction.beginExport()
        interaction.panelDropExited()
        check(interaction.phase == .exporting && !interaction.isShowingDetails, "export closes old details and remains exporting after drop-target cancellation")
        interaction.showReturningShelfItem()
        interaction.resumeExport()
        check(interaction.phase == .exporting, "self-drop rejection can resume export")
        for (index, file) in files.enumerated() {
            check(try Data(contentsOf: file) == Data("original-\(index)".utf8), "interaction tests never alter source content")
        }
        print("Shelf interaction smoke passed: status/panel cancelled drops, replacement/partial undo, committed outcomes, counts, reset/details, export state, source integrity")
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("Failed: \(message)") }
    }
}
