import AppKit

/// Exercises native hit testing without creating a window or injecting UI events.
@main struct ShelfDropTargetSmoke {
    @MainActor static func main() {
        let suite = "ShelfDropTargetSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShelfStore(defaults: defaults)
        let state = ShelfInteractionState()
        let host = ShelfHostingView(store: store, interaction: state)
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 240))
        host.frame = NSRect(x: 31, y: 27, width: DockShelfMetrics.panelSize.width, height: DockShelfMetrics.panelSize.height)
        parent.addSubview(host)
        precondition(host.registeredDraggedTypes.contains(.fileURL))
        precondition(host.registeredDraggedTypes.contains(ShelfImport.sourceType))
        precondition(!host.isOpaque && (host.layer?.backgroundColor?.alpha ?? 0) > 0)
        precondition((host.layer?.backgroundColor?.alpha ?? 1) <= 0.02)
        var count = 0
        // Blank margins, spaces between files, the entire ledge and its right end.
        for y in [1.0, 20, 70, 90, 105, 130, 160, 194] {
            for x in [1.0, 20, 75, 150, 240, 330, 398, 418] {
                let point = NSPoint(x: x + host.frame.minX, y: y + host.frame.minY)
                guard let hit = host.hitTest(point) else { fatalError("No receiver at \(x),\(y)") }
                var current: NSView? = hit
                while let view = current, view !== host { current = view.superview }
                precondition(current === host, "Hits must belong to the native file destination")
                count += 1
            }
        }
        precondition(host.hitTest(NSPoint(x: 20, y: 20)) == nil)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.writeObjects([URL(fileURLWithPath: "/fixture/file.txt") as NSURL])
        precondition(ShelfImport.accepts(board), "External file accepted on whole destination")
        board.setString("own", forType: ShelfImport.sourceType)
        precondition(!ShelfImport.accepts(board), "Expanded target still rejects self-drop")
        print("Drop target checks passed: \(count) native hit points, transparent backing, receiver ancestry, bounds, file and self-drop rules. WindowServer drag delivery remains a manual check.")
    }
}
