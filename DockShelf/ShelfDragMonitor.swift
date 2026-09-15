import AppKit

/// A new drag pasteboard owner plus a held, moved mouse distinguishes a fresh drag
/// from old file data left on the drag pasteboard. This policy does not read paths.
struct ShelfDragDetection {
    private var baseline: Int?
    private var startPoint = NSPoint.zero
    private var startTime: TimeInterval = 0
    private(set) var didPresent = false

    mutating func begin(changeCount: Int, point: NSPoint, time: TimeInterval) {
        baseline = changeCount
        startPoint = point
        startTime = time
        didPresent = false
    }

    mutating func update(changeCount: Int, hasFiles: Bool, isOwnDrag: Bool, point: NSPoint, time: TimeInterval) -> Bool {
        guard let baseline, !didPresent, changeCount != baseline,
              hasFiles, !isOwnDrag, time - startTime >= 0.12,
              hypot(point.x - startPoint.x, point.y - startPoint.y) >= 8 else { return false }
        didPresent = true
        return true
    }

    @discardableResult
    mutating func end() -> Bool {
        let wasPresented = didPresent
        baseline = nil
        didPresent = false
        return wasPresented
    }
}

/// Observes mouse button boundaries only. Polls drag metadata while held, never
/// the general clipboard or arbitrary keys. Does not synthesize any input.
@MainActor
final class ShelfDragMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var timer: Timer?
    private var detection = ShelfDragDetection()
    private let onStart: () -> Void
    private let onEnd: () -> Void
    var isMonitoring: Bool { globalMonitor != nil && localMonitor != nil }

    init(onStart: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.onStart = onStart
        self.onEnd = onEnd
    }

    @discardableResult
    func start() -> Bool {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event.type) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event.type)
            return event
        }
        guard isMonitoring else {
            stop()
            NSLog("Shelf automatic drag monitor unavailable")
            return false
        }
        return true
    }

    func stop() {
        finishGesture()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ type: NSEvent.EventType) {
        if type == .leftMouseUp {
            finishGesture()
            return
        }
        finishGesture()
        detection.begin(changeCount: NSPasteboard(name: .drag).changeCount,
                        point: NSEvent.mouseLocation, time: ProcessInfo.processInfo.systemUptime)
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.015
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func sample() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            finishGesture()
            return
        }
        let pasteboard = NSPasteboard(name: .drag)
        let point = NSEvent.mouseLocation
        if detection.update(changeCount: pasteboard.changeCount,
                            hasFiles: pasteboard.availableType(from: [.fileURL]) != nil,
                            isOwnDrag: ShelfImport.isShelfDrag(pasteboard),
                            point: point, time: ProcessInfo.processInfo.systemUptime) {
            onStart()
        }
    }

    private func finishGesture() {
        timer?.invalidate()
        timer = nil
        if detection.end() { onEnd() }
    }

    deinit {
        timer?.invalidate()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
