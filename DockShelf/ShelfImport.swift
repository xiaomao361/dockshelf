import AppKit
import SwiftUI

/// Reads only original file references from a drag pasteboard, never file contents or promises.
enum ShelfImport {
    static let sourceType = NSPasteboard.PasteboardType("com.claracore.dockshelf.shelf-item")

    struct Batch {
        let urls: [URL]
        let failedCount: Int
    }

    static func read(_ pasteboard: NSPasteboard) -> Batch {
        let itemCount = pasteboard.pasteboardItems?.count ?? 0
        let values = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] ?? []
        let urls = values.map { $0 as URL }.filter(\.isFileURL)
        return Batch(urls: urls, failedCount: max(0, itemCount - urls.count))
    }

    static func isShelfDrag(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [sourceType]) != nil
    }

    static func accepts(_ pasteboard: NSPasteboard) -> Bool {
        !isShelfDrag(pasteboard) && pasteboard.availableType(from: [.fileURL]) != nil
    }
}

/// The whole hosting view receives native file drops without an overlay over SwiftUI controls.
@MainActor
final class ShelfHostingView: NSHostingView<ShelfView> {
    private let store: ShelfStore
    private let interaction: ShelfInteractionState

    init(store: ShelfStore, interaction: ShelfInteractionState) {
        self.store = store
        self.interaction = interaction
        super.init(rootView: ShelfView(store: store, interaction: interaction))
        registerForDraggedTypes([.fileURL, .string, ShelfImport.sourceType])
    }

    @available(*, unavailable)
    required init(rootView: ShelfView) { fatalError("Use init(store:interaction:)") }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(store:interaction:)") }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if ShelfImport.isShelfDrag(sender.draggingPasteboard) {
            interaction.showReturningShelfItem()
            return []
        }
        let valid = ShelfImport.accepts(sender.draggingPasteboard)
        interaction.panelDropEntered(isValid: valid)
        return valid ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        ShelfImport.accepts(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        if interaction.phase == .returningShelfItem {
            interaction.resumeExport()
        } else {
            interaction.panelDropExited()
        }
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        ShelfImport.accepts(sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard !ShelfImport.isShelfDrag(sender.draggingPasteboard) else {
            interaction.resumeExport()
            return false
        }
        let batch = ShelfImport.read(sender.draggingPasteboard)
        let result = store.add(batch.urls, failedCount: batch.failedCount)
        // Counts only: no private paths, names or file content in diagnostics.
        NSLog("Shelf native drop: urls=%ld unreadable=%ld accepted=%@", batch.urls.count, batch.failedCount, result.accepted ? "true" : "false")
        interaction.finishDrop(result: result)
        return result.accepted
    }
}
